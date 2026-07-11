#!/bin/sh
# config.sh — managed config link staging, activation, and reconciliation.
#
# Config links are the bridge between what a module declares and what lands
# on the user's filesystem. The key invariant: no external symlink is created
# until hw_config_activate is called — staging is purely within the generation
# directory.

# hw_config_link src dest module_name gen_path
# Stage a config file from the module's config/ directory and record the link.
# src is relative to module_path/config/. dest is an absolute path on the system.
hw_config_link() {
    _hcl_src="$1"
    _hcl_dest="$2"
    _hcl_module="$3"
    _hcl_gen="$4"

    # HOMEWORLD_MODULE_ROOT must be set by the install.sh environment
    _hcl_module_root="${HOMEWORLD_MODULE_ROOT:-}"
    if [ -z "$_hcl_module_root" ]; then
        hw_die "HOMEWORLD_MODULE_ROOT is not set — config link can only be called during module installation"
    fi

    # Validate the source path cannot escape the config directory
    _hcl_safe_src=$(hw_safe_path "$_hcl_module_root/config" "$_hcl_src")
    if [ ! -e "$_hcl_safe_src" ]; then
        hw_die "config source does not exist: $_hcl_safe_src" \
               "The path must be relative to the module's config/ directory."
    fi

    # Check the dest is absolute — we're creating a real filesystem link
    case "$_hcl_dest" in
        /*) ;;
        *)  hw_die "config link destination must be an absolute path: '$_hcl_dest'" \
                   "Use a full path like \"\$HOME/.config/myfile\" rather than a relative one." ;;
    esac

    _hcl_links_file="$_hcl_gen/.homeworld/managed-links"
    _hcl_staged_dir="$_hcl_gen/config/$_hcl_module"

    # Ensure another module hasn't already claimed this destination
    if [ -f "$_hcl_links_file" ]; then
        while IFS='|' read -r _hcl_existing_dest _hcl_existing_src; do
            if [ "$_hcl_existing_dest" = "$_hcl_dest" ]; then
                # It's fine if the same module re-declares the same link
                # (idempotent re-runs of install.sh)
                _hcl_existing_mod=$(printf '%s' "$_hcl_existing_src" | sed "s|$_hcl_gen/config/||" | cut -d/ -f1)
                if [ "$_hcl_existing_mod" != "$_hcl_module" ]; then
                    hw_die "config link conflict: '$_hcl_dest' is already managed by module '$_hcl_existing_mod'" \
                           "Each destination can only be managed by one module — remove the duplicate link declaration."
                fi
                # Same module, same dest — treat as re-declaration and skip
                return 0
            fi
        done < "$_hcl_links_file"
    fi

    # Stage the file/dir into the generation's config area
    _hcl_staged_src="$_hcl_staged_dir/$_hcl_src"
    mkdir -p "$(dirname "$_hcl_staged_src")"

    if [ -d "$_hcl_safe_src" ]; then
        cp -r "$_hcl_safe_src" "$_hcl_staged_src"
    else
        cp "$_hcl_safe_src" "$_hcl_staged_src"
    fi

    # Append the mapping to the managed-links manifest
    printf '%s|%s\n' "$_hcl_dest" "$_hcl_staged_src" >> "$_hcl_links_file"
}

# hw_config_activate gen_path
# Create external symlinks for all entries in managed-links.
# Writes progress to activation journal so recovery is possible.
hw_config_activate() {
    _hca_gen="$1"
    _hca_links="$_hca_gen/.homeworld/managed-links"
    _hca_journal="$_hca_gen/.homeworld/activation-journal"

    [ -f "$_hca_links" ] || return 0

    while IFS='|' read -r _hca_dest _hca_src; do
        [ -n "$_hca_dest" ] || continue

        # Guard against overwriting unmanaged files.
        # A symlink pointing anywhere that isn't a Homeworld-managed path
        # is considered unmanaged — we won't touch it.
        if [ -e "$_hca_dest" ] || [ -L "$_hca_dest" ]; then
            if [ ! -L "$_hca_dest" ]; then
                hw_die "config destination '$_hca_dest' is an unmanaged file or directory" \
                       "Homeworld will not overwrite unmanaged files. Move or remove it, then re-run 'homeworld install'."
            fi
            # It's a symlink; check if it points inside HW_DATA (managed) or elsewhere
            _hca_existing=$(readlink "$_hca_dest")
            case "$_hca_existing" in
                "$HW_DATA"*) ;; # managed by homeworld, ok to update
                *)
                    hw_die "config destination '$_hca_dest' points to an unmanaged path — homeworld will not overwrite it" \
                           "Remove the symlink manually and re-run 'homeworld install': rm '$_hca_dest'"
                    ;;
            esac
        fi

        # Create parent directory if needed
        mkdir -p "$(dirname "$_hca_dest")"

        ln -sf "$_hca_src" "$_hca_dest"

        # Journal each created link so interrupted activation can be diagnosed
        printf 'linked: %s -> %s\n' "$_hca_dest" "$_hca_src" >> "$_hca_journal"
    done < "$_hca_links"
}

# hw_config_reconcile prev_gen_path gen_path
# Remove external links that belonged to prev_gen but are no longer in gen.
# Only removes a link if it still points to its expected previous-generation target;
# if the user has changed it, warn and leave it alone.
hw_config_reconcile() {
    _hcr_prev="$1"
    _hcr_new="$2"
    _hcr_prev_links="$_hcr_prev/.homeworld/managed-links"
    _hcr_new_links="$_hcr_new/.homeworld/managed-links"

    [ -f "$_hcr_prev_links" ] || return 0

    while IFS='|' read -r _hcr_dest _hcr_prev_src; do
        [ -n "$_hcr_dest" ] || continue

        # Check if the new generation also manages this destination
        _hcr_in_new=0
        if [ -f "$_hcr_new_links" ]; then
            while IFS='|' read -r _hcr_new_dest _hcr_new_src; do
                [ "$_hcr_new_dest" = "$_hcr_dest" ] && { _hcr_in_new=1; break; }
            done < "$_hcr_new_links"
        fi

        # If the new generation declares it, the activation already updated it
        [ "$_hcr_in_new" = "1" ] && continue

        # The new generation dropped this link — remove it if it still points
        # where we expect. If the user modified it, warn but don't destroy.
        if [ -L "$_hcr_dest" ]; then
            _hcr_current_target=$(readlink "$_hcr_dest")
            if [ "$_hcr_current_target" = "$_hcr_prev_src" ]; then
                rm -f "$_hcr_dest"
                hw_log "removed stale config link: $_hcr_dest"
            else
                hw_warn "config link '$_hcr_dest' has been modified externally (expected -> $_hcr_prev_src, found -> $_hcr_current_target) — leaving it"
            fi
        fi
    done < "$_hcr_prev_links"
}
