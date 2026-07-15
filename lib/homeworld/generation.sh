#!/bin/sh
# generation.sh — immutable generation lifecycle and reachability cleanup.

hw_gen_id() {
    _hgi_date=$(date +%Y%m%d)
    _hgi_rand=$(od -An -N3 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | sed 's/^\(.\{6\}\).*/\1/')
    [ -n "$_hgi_rand" ] || _hgi_rand=$(printf '%06x' "$$" 2>/dev/null || printf 000000)
    printf '%s-%s' "$_hgi_date" "$_hgi_rand"
}

hw_gen_new() {
    mkdir -p "$HW_DATA/generations" "$(hw_mirrors_dir)" "$(hw_checkouts_dir)" "$(hw_orphaned_dir)" "$HW_STATE/locks"
    _hgn_path="$HW_DATA/generations/$(hw_gen_id)"
    mkdir -p "$_hgn_path/assets" "$_hgn_path/bin" "$_hgn_path/commands" "$_hgn_path/config" "$_hgn_path/repos" "$_hgn_path/.homeworld"
    hw_schema_write "$_hgn_path/.homeworld"
    hw_atomic_write "$_hgn_path/.homeworld/status" pending
    printf '%s' "$_hgn_path"
}

hw_gen_write_meta() {
    _hwm_path=$1; _hwm_platform=$2; _hwm_distro=$3; _hwm_provider=$4; _hwm_modules=$5
    _hwm_meta="$_hwm_path/.homeworld"
    hw_schema_write "$_hwm_meta"
    hw_atomic_write "$_hwm_meta/platform" "$_hwm_platform"
    hw_atomic_write "$_hwm_meta/distro" "$_hwm_distro"
    hw_atomic_write "$_hwm_meta/package-provider" "$_hwm_provider"
    printf '%s\n' $_hwm_modules > "$_hwm_meta/installed-modules"
    hw_atomic_write "$_hwm_meta/created-at" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    _hwm_source=''; [ -f "$HW_STATE/source" ] && _hwm_source=$(cat "$HW_STATE/source")
    _hwm_rev=local
    if [ -n "$_hwm_source" ] && command -v git >/dev/null 2>&1; then
        _hwm_rev=$(git -C "$_hwm_source" rev-parse HEAD 2>/dev/null || printf local)
    fi
    hw_atomic_write "$_hwm_meta/source-revision" "$_hwm_rev"
}

hw_gen_activate_locked() {
    _hga_gen=$1
    [ -d "$_hga_gen/.homeworld" ] || hw_die "generation metadata is missing: $_hga_gen"
    hw_schema_check "$_hga_gen/.homeworld" true
    _hga_old=''; [ -L "$(hw_current)" ] && _hga_old=$(readlink "$(hw_current)")
    hw_managed_link_prepare_views "$_hga_gen"
    hw_managed_link_validate "$_hga_old" "$_hga_gen"
    hw_transaction_begin "$_hga_gen"
    hw_test_interrupt after-journal
    trap 'hw_transaction_present && hw_transaction_repair_locked' EXIT
    trap 'hw_transaction_present && hw_transaction_repair_locked; exit 143' HUP INT TERM

    # Previous always records the generation that was active before this swap.
    if [ -n "$_hga_old" ]; then
        hw_symlink_replace "$_hga_old" "$(hw_previous)" || { hw_transaction_repair_locked; trap - EXIT
    trap - HUP INT TERM; hw_die "could not update previous generation"; }
        hw_test_interrupt after-previous
    fi
    hw_symlink_replace "$_hga_gen" "$(hw_current)" || { hw_transaction_repair_locked; trap - EXIT
    trap - HUP INT TERM; hw_die "could not activate generation"; }
    hw_test_interrupt after-current
    hw_transaction_phase current-swapped
    hw_test_interrupt after-current-phase

    if ! hw_managed_link_apply_locked "$_hga_old" "$_hga_gen"; then
        hw_transaction_repair_locked
        trap - EXIT
    trap - HUP INT TERM
        hw_die "could not reconcile managed links"
    fi
    hw_test_interrupt after-bindings
    hw_transaction_phase bindings-reconciled
    hw_test_interrupt after-bindings-phase
    hw_atomic_write "$_hga_gen/.homeworld/status" active
    [ -z "$_hga_old" ] || hw_atomic_write "$_hga_old/.homeworld/status" retained
    hw_transaction_finish
    trap - EXIT
    trap - HUP INT TERM
}

hw_gen_activate() {
    _hga_lock=$(hw_global_lock_dir)
    hw_lock_acquire "$_hga_lock" "generation activation"
    trap 'hw_lock_release "$_hga_lock"' EXIT HUP INT TERM
    hw_transaction_repair_locked
    hw_gen_activate_locked "$1"
    hw_lock_release "$_hga_lock"
    trap - EXIT
    trap - HUP INT TERM
}

hw_gen_rollback() {
    [ -L "$(hw_current)" ] || hw_die "no active generation to roll back from"
    [ -L "$(hw_previous)" ] || hw_die "no previous generation to roll back to"
    _hgr_target=$(readlink "$(hw_previous)")
    hw_gen_activate "$_hgr_target"
}

hw_gen_list() {
    [ -d "$HW_DATA/generations" ] || return 0
    for _hgl_path in "$HW_DATA/generations"/*; do
        [ -d "$_hgl_path" ] || continue
        printf '%s\n' "$_hgl_path"
    done | sort -r | while IFS= read -r _hgl_path; do
        _hgl_marker=''
        [ -L "$(hw_current)" ] && [ "$(readlink "$(hw_current)")" = "$_hgl_path" ] && _hgl_marker=' (current)'
        [ -z "$_hgl_marker" ] && [ -L "$(hw_previous)" ] && [ "$(readlink "$(hw_previous)")" = "$_hgl_path" ] && _hgl_marker=' (previous)'
        printf '%s%s\n' "$(basename "$_hgl_path")" "$_hgl_marker"
    done
}

hw_gen_gc_locked() {
    _hgg_current=''; _hgg_previous=''
    [ -L "$(hw_current)" ] && _hgg_current=$(readlink "$(hw_current)")
    [ -L "$(hw_previous)" ] && _hgg_previous=$(readlink "$(hw_previous)")
    for _hgg_path in "$HW_DATA/generations"/*; do
        [ -d "$_hgg_path" ] || continue
        [ "$_hgg_path" = "$_hgg_current" ] && continue
        [ "$_hgg_path" = "$_hgg_previous" ] && continue
        [ "$(cat "$_hgg_path/.homeworld/status" 2>/dev/null)" = pending ] && continue
        hw_tree_make_removable "$_hgg_path"
        rm -rf "$_hgg_path"
    done
    hw_repo_gc_locked
}

hw_gen_gc() {
    _hgg_lock=$(hw_global_lock_dir)
    hw_lock_acquire "$_hgg_lock" "generation cleanup"
    trap 'hw_lock_release "$_hgg_lock"' EXIT HUP INT TERM
    hw_transaction_repair_locked
    hw_gen_gc_locked
    hw_lock_release "$_hgg_lock"
    trap - EXIT
    trap - HUP INT TERM
}

# Compatibility entry point used by older callers.
hw_gen_repair() { hw_transaction_repair; }
