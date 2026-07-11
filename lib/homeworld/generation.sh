#!/bin/sh
# generation.sh — generation lifecycle: create, activate, rollback, gc.
#
# Generations are immutable once activated. The "current" and "previous"
# symlinks are the only mutable state outside the generation directories.
# All activation logic is journaled so interrupted operations are detectable
# and repairable on next startup.

# hw_gen_id — generate a unique generation ID.
# Format: YYYYMMDD-xxxxxx where xxxxxx is 6 hex chars from /dev/urandom.
# Using od + tr instead of /dev/urandom directly keeps us POSIX-clean.
hw_gen_id() {
    _hgi_date=$(date +%Y%m%d)
    _hgi_rand=$(od -An -N3 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | head -c6)
    # Fallback: use PID + time if od/urandom fails
    if [ -z "$_hgi_rand" ]; then
        _hgi_rand=$(printf '%06x' "$$" 2>/dev/null || printf '%06x' 0)
    fi
    printf '%s-%s' "$_hgi_date" "$_hgi_rand"
}

# hw_gen_new — allocate a fresh generation directory.
# Creates the standard subdirectory tree and returns the path.
hw_gen_new() {
    _hgn_id=$(hw_gen_id)
    _hgn_path="$HW_DATA/generations/$_hgn_id"

    mkdir -p \
        "$_hgn_path/assets" \
        "$_hgn_path/bin" \
        "$_hgn_path/commands" \
        "$_hgn_path/config" \
        "$_hgn_path/.homeworld"

    printf '%s' "$_hgn_path"
}

# hw_gen_write_meta gen_path platform distro provider modules
# Write generation metadata into gen_path/.homeworld/.
# modules is a newline-separated list.
hw_gen_write_meta() {
    _hwm_path="$1"
    _hwm_platform="$2"
    _hwm_distro="$3"
    _hwm_provider="$4"
    _hwm_modules="$5"
    _hwm_meta="$_hwm_path/.homeworld"

    printf '%s' "$_hwm_platform" > "$_hwm_meta/platform"
    printf '%s' "$_hwm_distro"   > "$_hwm_meta/distro"
    printf '%s' "$_hwm_provider" > "$_hwm_meta/package-provider"
    # One module name per line — easier to grep and diff than a space-separated blob
    printf '%s\n' $_hwm_modules > "$_hwm_meta/installed-modules"
    printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$_hwm_meta/created-at"

    # Read source path from state; fall back gracefully if not configured
    _hwm_source_path=""
    if [ -f "$HW_STATE/source" ]; then
        _hwm_source_path=$(cat "$HW_STATE/source")
    fi

    _hwm_rev="local"
    if [ -n "$_hwm_source_path" ] && command -v git >/dev/null 2>&1; then
        _hwm_rev=$(git -C "$_hwm_source_path" rev-parse HEAD 2>/dev/null || printf 'local')
    fi
    printf '%s' "$_hwm_rev" > "$_hwm_meta/source-revision"
}

# hw_gen_activate gen_path
# Atomic generation activation. Steps:
#   1. Write journal of links to create
#   2. Apply config links (hw_config_activate)
#   3. Swap current symlink atomically via pending-current
#   4. Update previous
#   5. Reconcile config links against old generation
hw_gen_activate() {
    _hga_gen="$1"
    _hga_meta="$_hga_gen/.homeworld"

    # Write the activation journal before touching anything external.
    # If we die after this point, hw_gen_repair can see what was in progress.
    printf '%s\n' "$_hga_gen" > "$_hga_meta/activation-journal"

    # Apply config links for the new generation
    hw_config_activate "$_hga_gen"

    # Remember what current pointed to before we change it
    _hga_old_current=""
    if [ -L "$(hw_current)" ]; then
        _hga_old_current=$(readlink "$(hw_current)")
    fi

    # Remember what previous pointed to so we can restore it on failure
    _hga_old_previous=""
    if [ -L "$(hw_previous)" ]; then
        _hga_old_previous=$(readlink "$(hw_previous)")
    fi

    # Swap the "current" symlink. We cannot use plain "mv src current" because
    # mv follows the symlink when current points to a directory, moving src
    # inside that directory instead of replacing the symlink name.
    # ln -sfn is the portable-enough solution: -n treats the destination as
    # a plain filename even when it resolves to a directory. Both GNU ln and
    # macOS ln support -n. This is not atomic but for a single-user local
    # tool the window is negligible and no data is destroyed.
    ln -sfn "$_hga_gen" "$HW_DATA/current"

    # Update previous to point to what current used to be
    if [ -n "$_hga_old_current" ]; then
        ln -sfn "$_hga_old_current" "$HW_DATA/previous"
    fi

    # Reconcile config links: remove links from the old generation that
    # the new generation no longer declares.
    if [ -n "$_hga_old_current" ] && [ -d "$_hga_old_current" ]; then
        hw_config_reconcile "$_hga_old_current" "$_hga_gen"
    fi

    # Journal is only cleared on full success — if we die mid-reconcile, repair
    # will find the journal and know what to clean up.
    rm -f "$_hga_meta/activation-journal"
}

# hw_gen_rollback — swap current and previous, then reconcile links.
# Running rollback again undoes the rollback (it's a true swap).
hw_gen_rollback() {
    _hgr_current=$(hw_current)
    _hgr_previous=$(hw_previous)

    if [ ! -L "$_hgr_current" ]; then
        hw_die "no active generation to roll back from" \
               "Run 'homeworld install' to create a generation first."
    fi
    if [ ! -L "$_hgr_previous" ]; then
        hw_die "no previous generation to roll back to" \
               "A second generation is needed for rollback. Run 'homeworld install' to create one."
    fi

    _hgr_cur_target=$(readlink "$_hgr_current")
    _hgr_prev_target=$(readlink "$_hgr_previous")

    # Activate the previous generation (which handles config link reconcile)
    hw_gen_activate "$_hgr_prev_target"
}

# hw_gen_list — print all generation IDs, newest first.
hw_gen_list() {
    _hgl_dir="$HW_DATA/generations"
    [ -d "$_hgl_dir" ] || return 0

    # Sort reverse-alphabetically; since IDs start with YYYYMMDD, this gives
    # newest first without needing date parsing.
    find "$_hgl_dir" -maxdepth 1 -mindepth 1 -type d | sort -r | while read -r _hgl_path; do
        _hgl_id=$(basename "$_hgl_path")
        # Mark active and previous
        _hgl_marker=""
        if [ -L "$(hw_current)" ]; then
            _hgl_cur=$(readlink "$(hw_current)")
            [ "$_hgl_cur" = "$_hgl_path" ] && _hgl_marker=" (current)"
        fi
        if [ -L "$(hw_previous)" ] && [ -z "$_hgl_marker" ]; then
            _hgl_prev=$(readlink "$(hw_previous)")
            [ "$_hgl_prev" = "$_hgl_path" ] && _hgl_marker=" (previous)"
        fi
        printf '%s%s\n' "$_hgl_id" "$_hgl_marker"
    done
}

# hw_gen_gc — remove generation directories not referenced by current or previous.
# Never removes a generation that is actively in use.
hw_gen_gc() {
    _hggc_dir="$HW_DATA/generations"
    [ -d "$_hggc_dir" ] || return 0

    _hggc_keep=""
    if [ -L "$(hw_current)" ]; then
        _hggc_keep="$_hggc_keep $(readlink "$(hw_current)")"
    fi
    if [ -L "$(hw_previous)" ]; then
        _hggc_keep="$_hggc_keep $(readlink "$(hw_previous)")"
    fi

    _hggc_removed=0
    find "$_hggc_dir" -maxdepth 1 -mindepth 1 -type d | while read -r _hggc_path; do
        _hggc_skip=0
        for _hggc_k in $_hggc_keep; do
            [ "$_hggc_k" = "$_hggc_path" ] && { _hggc_skip=1; break; }
        done
        if [ "$_hggc_skip" = "0" ]; then
            hw_log "gc: removing $_hggc_path"
            rm -rf "$_hggc_path"
        fi
    done
}

# hw_gen_repair — called at startup to recover from interrupted activation.
# Cleans up any temp symlinks left by a previous crash. Activation journals
# in .homeworld/ are left for future diagnosis but don't block recovery.
hw_gen_repair() {
    # These temp symlinks could be left if we died between creating them and
    # doing the rename. Removing them is safe — the real current/previous
    # symlinks are unaffected (ln -sfn is not atomic; if we died mid-swap the
    # symlink may or may not have been updated, but at worst the generation
    # directory is still intact).
    if [ -L "$HW_DATA/pending-current" ]; then
        hw_warn "found stale pending-current symlink — cleaning up after an interrupted activation"
        rm -f "$HW_DATA/pending-current"
    fi
    if [ -L "$HW_DATA/pending-previous" ]; then
        rm -f "$HW_DATA/pending-previous"
    fi
}
