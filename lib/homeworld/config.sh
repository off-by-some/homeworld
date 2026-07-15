#!/bin/sh
# config.sh — generation resources and managed external bindings.

hw_managed_links_dir() { printf '%s/.homeworld/managed-links' "$1"; }

hw_metadata_id() {
    _hmi_value=$1
    if command -v git >/dev/null 2>&1; then printf '%s' "$_hmi_value" | git hash-object --stdin; else printf '%s' "$_hmi_value" | cksum | awk '{print $1}'; fi
}

hw_copy_resource() {
    _hcr_source=$1
    _hcr_dest=$2
    [ ! -L "$_hcr_source" ] || hw_die "resource source is a symlink; resolve the link before staging"
    [ -e "$_hcr_source" ] || hw_die "resource source does not exist: $_hcr_source"
    _hcr_parent=$(dirname "$_hcr_dest")
    _hcr_tmp="$_hcr_parent/.tmp-$(basename "$_hcr_dest").$$"
    mkdir -p "$_hcr_parent"
    rm -rf "$_hcr_tmp"
    if [ -d "$_hcr_source" ]; then
        mkdir -p "$_hcr_tmp"
        cp -R "$_hcr_source/." "$_hcr_tmp/" || { rm -rf "$_hcr_tmp"; hw_die "could not stage resource"; }
    else
        cp "$_hcr_source" "$_hcr_tmp" || { rm -f "$_hcr_tmp"; hw_die "could not stage resource"; }
    fi
    rm -rf "$_hcr_dest"
    mv "$_hcr_tmp" "$_hcr_dest" || hw_die "could not publish staged resource"
}

hw_config_resource_id() {
    _hcri_source=$1
    case "$_hcri_source" in config/*) printf '%s' "${_hcri_source#config/}" ;; *) printf '%s' "$_hcri_source" ;; esac
}

hw_config_add() {
    _hca_source=$1; _hca_gen=$2; _hca_module=$3
    case "$_hca_source" in /*) hw_die "config source must be relative to the module root" ;; esac
    _hca_root=${HOMEWORLD_MODULE_ROOT:-}
    [ -n "$_hca_root" ] || hw_die "config add can only be called during module installation"
    _hca_safe=$(hw_safe_path "$_hca_root" "$_hca_source") || hw_die "invalid config source path"
    _hca_id=$(hw_config_resource_id "$_hca_source")
    _hca_dest=$(hw_safe_path "$_hca_gen/config/$_hca_module" "$_hca_id") || hw_die "invalid config resource path"
    hw_copy_resource "$_hca_safe" "$_hca_dest"
    printf '%s' "$_hca_id"
}

hw_asset_add() {
    _haa_source=$1; _haa_name=$2; _haa_gen=$3; _haa_module=$4
    hw_validate_name "$_haa_name" "asset name"
    case "$_haa_source" in
        /*) _haa_safe=$_haa_source ;;
        *)
            _haa_root=${HOMEWORLD_MODULE_ROOT:-}
            [ -n "$_haa_root" ] || hw_die "asset add can only be called during module installation"
            _haa_safe=$(hw_safe_path "$_haa_root" "$_haa_source") || hw_die "invalid asset source path"
            ;;
    esac
    hw_copy_resource "$_haa_safe" "$_haa_gen/assets/$_haa_module/$_haa_name"
}

hw_managed_link_record() {
    _hmlr_dest=$1; _hmlr_type=$2; _hmlr_id=$3; _hmlr_module=$4; _hmlr_gen=$5; _hmlr_kind=${6:-generation}; _hmlr_expected=${7:-}
    hw_reject_line_breaks "$_hmlr_dest" "link destination"
    case "$_hmlr_dest" in /*) : ;; *) hw_die "link destination must be an absolute path: $_hmlr_dest" ;; esac
    _hmlr_root=$(hw_managed_links_dir "$_hmlr_gen")
    mkdir -p "$_hmlr_root"
    [ -f "$_hmlr_root/schema-version" ] || hw_schema_write "$_hmlr_root"
    _hmlr_key=$(hw_metadata_id "$_hmlr_dest|$_hmlr_type|$_hmlr_id|$_hmlr_module")
    _hmlr_dir="$_hmlr_root/$_hmlr_key"
    _hmlr_tmp="${_hmlr_dir}.tmp-$$"
    rm -rf "$_hmlr_tmp"; mkdir -p "$_hmlr_tmp"
    hw_schema_write "$_hmlr_tmp"
    hw_atomic_write "$_hmlr_tmp/dest" "$_hmlr_dest"
    hw_atomic_write "$_hmlr_tmp/type" "$_hmlr_type"
    hw_atomic_write "$_hmlr_tmp/id" "$_hmlr_id"
    hw_atomic_write "$_hmlr_tmp/module" "$_hmlr_module"
    hw_atomic_write "$_hmlr_tmp/kind" "$_hmlr_kind"
    hw_atomic_write "$_hmlr_tmp/expected-type" "$_hmlr_expected"
    rm -rf "$_hmlr_dir"; mv "$_hmlr_tmp" "$_hmlr_dir" || hw_die "cannot record managed link"
}

hw_config_link() {
    _hcl_source=$1; _hcl_dest=$2; _hcl_module=$3; _hcl_gen=$4
    _hcl_id=$(hw_config_add "$_hcl_source" "$_hcl_gen" "$_hcl_module") || hw_die "could not add config resource"
    hw_managed_link_record "$_hcl_dest" config "$_hcl_module/$_hcl_id" "$_hcl_module" "$_hcl_gen"
}

hw_asset_link() {
    _hal_source=$1; _hal_name=$2; _hal_dest=$3; _hal_gen=$4; _hal_module=$5
    hw_asset_add "$_hal_source" "$_hal_name" "$_hal_gen" "$_hal_module"
    hw_managed_link_record "$_hal_dest" asset "$_hal_module/$_hal_name" "$_hal_module" "$_hal_gen"
}

hw_repo_link() {
    _hrl_ns=$1; _hrl_dest=$2; _hrl_gen=$3; _hrl_module=$4
    [ -e "$_hrl_gen/repos/$_hrl_ns" ] || [ -L "$_hrl_gen/repos/$_hrl_ns" ] || hw_die "repository is not part of the pending generation: $_hrl_ns"
    hw_managed_link_record "$_hrl_dest" repo "$_hrl_ns" "$_hrl_module" "$_hrl_gen"
}

hw_state_link() {
    _hsl_value=$1; _hsl_dest=$2; _hsl_module=$3; _hsl_gen=$4
    case "$_hsl_value" in
        /*)
            _hsl_target=$_hsl_value; _hsl_kind=direct
            _hsl_type=$(hw_state_validate_target "$_hsl_target") || hw_die "state target is invalid"
            ;;
        *)
            hw_validate_name "$_hsl_value" "state name"
            _hsl_target=$(hw_state_bind_read "$_hsl_value") || hw_die "unknown state binding: $_hsl_value"
            _hsl_kind=named
            _hsl_type=$(hw_state_bind_type "$_hsl_value") ||
                _hsl_type=$(hw_state_validate_target "$_hsl_target") ||
                hw_die "state target is invalid"
            ;;
    esac
    hw_managed_link_record "$_hsl_dest" state "$_hsl_value" "$_hsl_module" "$_hsl_gen" "$_hsl_kind" "$_hsl_type"
}

hw_managed_link_is_nested() {
    [ -f "$1/nested-under" ]
}

hw_managed_link_generation_source() {
    _hmlgs_entry=$1
    _hmlgs_gen=$2
    _hmlgs_type=$(cat "$_hmlgs_entry/type")
    _hmlgs_id=$(cat "$_hmlgs_entry/id")
    case "$_hmlgs_type" in
        config) printf '%s/config/%s' "$_hmlgs_gen" "$_hmlgs_id" ;;
        asset) printf '%s/assets/%s' "$_hmlgs_gen" "$_hmlgs_id" ;;
        repo) printf '%s/repos/%s' "$_hmlgs_gen" "$_hmlgs_id" ;;
        *) return 1 ;;
    esac
}

# Build a directory made only of subdirectories and symlinks to immutable
# generation content. Paths that need nested state are expanded into real
# directories; untouched branches remain cheap symlinks.
hw_projection_populate_dir() {
    _hppd_source=$1
    _hppd_view=$2
    mkdir -p "$_hppd_view" || return 1
    for _hppd_item in "$_hppd_source"/* "$_hppd_source"/.[!.]* "$_hppd_source"/..?*; do
        [ -e "$_hppd_item" ] || [ -L "$_hppd_item" ] || continue
        _hppd_name=${_hppd_item##*/}
        ln -s "$_hppd_item" "$_hppd_view/$_hppd_name" || return 1
    done
}

hw_projection_insert_state() {
    _hpis_source=$1
    _hpis_view=$2
    _hpis_relative=$3
    _hpis_target=$4
    hw_reject_line_breaks "$_hpis_relative" "nested state path"
    case "/$_hpis_relative/" in
        */../* | */./* | *//*) hw_die "nested state destination contains an unsafe path component" ;;
    esac
    [ -n "$_hpis_relative" ] || hw_die "nested state destination cannot replace its managed parent"

    _hpis_source_cursor=$_hpis_source
    _hpis_view_cursor=$_hpis_view
    _hpis_remaining=$_hpis_relative
    while :; do
        case "$_hpis_remaining" in
            */*)
                _hpis_component=${_hpis_remaining%%/*}
                _hpis_remaining=${_hpis_remaining#*/}
                _hpis_source_next="$_hpis_source_cursor/$_hpis_component"
                _hpis_view_next="$_hpis_view_cursor/$_hpis_component"
                if [ -e "$_hpis_source_next" ] || [ -L "$_hpis_source_next" ]; then
                    [ -d "$_hpis_source_next" ] && [ ! -L "$_hpis_source_next" ] \
                        || hw_die "nested state destination crosses a non-directory repository path: $_hpis_relative"
                    if [ -L "$_hpis_view_next" ]; then
                        rm -f "$_hpis_view_next" || return 1
                        hw_projection_populate_dir "$_hpis_source_next" "$_hpis_view_next" || return 1
                    elif [ ! -d "$_hpis_view_next" ]; then
                        hw_die "nested state destination conflicts with another projection: $_hpis_relative"
                    fi
                else
                    if [ -e "$_hpis_view_next" ] || [ -L "$_hpis_view_next" ]; then
                        [ -d "$_hpis_view_next" ] && [ ! -L "$_hpis_view_next" ] \
                            || hw_die "nested state destination conflicts with another projection: $_hpis_relative"
                    else
                        mkdir -p "$_hpis_view_next" || return 1
                    fi
                fi
                _hpis_source_cursor=$_hpis_source_next
                _hpis_view_cursor=$_hpis_view_next
                ;;
            *)
                _hpis_source_final="$_hpis_source_cursor/$_hpis_remaining"
                _hpis_view_final="$_hpis_view_cursor/$_hpis_remaining"
                if [ -e "$_hpis_source_final" ] || [ -L "$_hpis_source_final" ]; then
                    hw_die "nested state destination conflicts with content supplied by the managed resource: $_hpis_relative"
                fi
                if [ -L "$_hpis_view_final" ] && [ "$(readlink "$_hpis_view_final")" = "$_hpis_target" ]; then
                    return 0
                fi
                if [ -e "$_hpis_view_final" ] || [ -L "$_hpis_view_final" ]; then
                    hw_die "nested state destination conflicts with another managed declaration: $_hpis_relative"
                fi
                hw_symlink_replace "$_hpis_target" "$_hpis_view_final" || return 1
                return 0
                ;;
        esac
    done
}

# Detect state destinations below managed directory links and realize them as
# generation-local composed views. The immutable repository or asset source is
# never modified. Named state points through a stable machine-local resolver.
hw_managed_link_prepare_views() {
    _hmpv_gen=$1
    _hmpv_root=$(hw_managed_links_dir "$_hmpv_gen")
    _hmpv_marker="$_hmpv_gen/.homeworld/projections-prepared"
    [ -f "$_hmpv_marker" ] && return 0
    [ -d "$_hmpv_root" ] || { hw_atomic_write "$_hmpv_marker" yes; return 0; }
    hw_schema_check "$_hmpv_root" false

    _hmpv_projection_root="$_hmpv_gen/.homeworld/projections"
    rm -rf "$_hmpv_projection_root"
    mkdir -p "$_hmpv_projection_root" || hw_die "cannot create managed resource projections"
    hw_schema_write "$_hmpv_projection_root"

    for _hmpv_entry in "$_hmpv_root"/*; do
        [ -d "$_hmpv_entry" ] || continue
        rm -f "$_hmpv_entry/projection" "$_hmpv_entry/nested-under" "$_hmpv_entry/nested-path"
    done

    # First reject state storage that would itself be hidden by a managed root.
    for _hmpv_state in "$_hmpv_root"/*; do
        [ -d "$_hmpv_state" ] || continue
        [ "$(cat "$_hmpv_state/type" 2>/dev/null)" = state ] || continue
        _hmpv_kind=$(cat "$_hmpv_state/kind" 2>/dev/null)
        _hmpv_id=$(cat "$_hmpv_state/id" 2>/dev/null)
        case "$_hmpv_kind" in
            named) _hmpv_state_target=$(hw_state_bind_read "$_hmpv_id") || hw_die "state binding is missing: $_hmpv_id" ;;
            direct) _hmpv_state_target=$_hmpv_id ;;
            *) hw_die "unknown state link kind: $_hmpv_kind" ;;
        esac
        hw_state_validate_target "$_hmpv_state_target" >/dev/null
        for _hmpv_parent in "$_hmpv_root"/*; do
            [ -d "$_hmpv_parent" ] || continue
            case "$(cat "$_hmpv_parent/type" 2>/dev/null)" in config|asset|repo) : ;; *) continue ;; esac
            _hmpv_parent_source=$(hw_managed_link_generation_source "$_hmpv_parent" "$_hmpv_gen") || continue
            [ -d "$_hmpv_parent_source" ] || continue
            _hmpv_parent_dest=$(cat "$_hmpv_parent/dest")
            hw_path_is_same_or_below "$_hmpv_state_target" "$_hmpv_parent_dest" \
                && hw_die "state target is inside a managed external destination: $_hmpv_state_target"
        done
    done

    # Attach each nested state declaration to its nearest managed directory.
    for _hmpv_state in "$_hmpv_root"/*; do
        [ -d "$_hmpv_state" ] || continue
        [ "$(cat "$_hmpv_state/type" 2>/dev/null)" = state ] || continue
        _hmpv_state_dest=$(cat "$_hmpv_state/dest")
        _hmpv_best=''; _hmpv_best_dest=''; _hmpv_best_length=0
        for _hmpv_parent in "$_hmpv_root"/*; do
            [ -d "$_hmpv_parent" ] || continue
            case "$(cat "$_hmpv_parent/type" 2>/dev/null)" in config|asset|repo) : ;; *) continue ;; esac
            _hmpv_parent_source=$(hw_managed_link_generation_source "$_hmpv_parent" "$_hmpv_gen") || continue
            [ -d "$_hmpv_parent_source" ] || continue
            _hmpv_parent_dest=$(cat "$_hmpv_parent/dest")
            hw_path_is_below "$_hmpv_state_dest" "$_hmpv_parent_dest" || continue
            _hmpv_length=${#_hmpv_parent_dest}
            if [ "$_hmpv_length" -gt "$_hmpv_best_length" ]; then
                _hmpv_best=$_hmpv_parent
                _hmpv_best_dest=$_hmpv_parent_dest
                _hmpv_best_length=$_hmpv_length
            fi
        done
        [ -n "$_hmpv_best" ] || continue
        _hmpv_key=${_hmpv_best##*/}
        _hmpv_relative=${_hmpv_state_dest#"$_hmpv_best_dest"/}
        hw_atomic_write "$_hmpv_state/nested-under" "$_hmpv_key"
        hw_atomic_write "$_hmpv_state/nested-path" "$_hmpv_relative"
        hw_atomic_write "$_hmpv_best/projection" "$_hmpv_key"
    done

    # Realize each parent projection after all nested declarations are known.
    for _hmpv_parent in "$_hmpv_root"/*; do
        [ -d "$_hmpv_parent" ] || continue
        [ -f "$_hmpv_parent/projection" ] || continue
        _hmpv_key=$(cat "$_hmpv_parent/projection")
        _hmpv_source=$(hw_managed_link_generation_source "$_hmpv_parent" "$_hmpv_gen") \
            || hw_die "cannot resolve managed projection source"
        [ -d "$_hmpv_source" ] || hw_die "nested state requires a managed directory resource"
        _hmpv_source=$(cd -P "$_hmpv_source" 2>/dev/null && pwd) \
            || hw_die "cannot resolve managed projection source"
        _hmpv_view="$_hmpv_projection_root/$_hmpv_key"
        hw_projection_populate_dir "$_hmpv_source" "$_hmpv_view" \
            || hw_die "cannot build managed resource projection"
        for _hmpv_state in "$_hmpv_root"/*; do
            [ -d "$_hmpv_state" ] || continue
            [ "$(cat "$_hmpv_state/nested-under" 2>/dev/null)" = "$_hmpv_key" ] || continue
            _hmpv_kind=$(cat "$_hmpv_state/kind")
            _hmpv_id=$(cat "$_hmpv_state/id")
            case "$_hmpv_kind" in
                named) _hmpv_target=$(hw_state_target_link "$_hmpv_id") ;;
                direct) _hmpv_target=$_hmpv_id ;;
                *) hw_die "unknown state link kind: $_hmpv_kind" ;;
            esac
            _hmpv_relative=$(cat "$_hmpv_state/nested-path")
            hw_projection_insert_state "$_hmpv_source" "$_hmpv_view" "$_hmpv_relative" "$_hmpv_target" \
                || hw_die "cannot insert nested state into managed resource projection"
        done
        find "$_hmpv_view" -type d -exec chmod a-w {} + 2>/dev/null || true
    done

    hw_atomic_write "$_hmpv_marker" yes
}

hw_managed_link_target() {
    _hmlt_entry=$1
    _hmlt_type=$(cat "$_hmlt_entry/type")
    _hmlt_id=$(cat "$_hmlt_entry/id")
    case "$_hmlt_type" in
        config|asset|repo)
            if [ -f "$_hmlt_entry/projection" ]; then
                printf '%s/.homeworld/projections/%s' "$(hw_current)" "$(cat "$_hmlt_entry/projection")"
            else
                case "$_hmlt_type" in
                    config) printf '%s/config/%s' "$(hw_current)" "$_hmlt_id" ;;
                    asset) printf '%s/assets/%s' "$(hw_current)" "$_hmlt_id" ;;
                    repo) printf '%s/repos/%s' "$(hw_current)" "$_hmlt_id" ;;
                esac
            fi
            ;;
        state)
            _hmlt_kind=$(cat "$_hmlt_entry/kind")
            case "$_hmlt_kind" in
                named)
                    hw_state_bind_read "$_hmlt_id" >/dev/null || hw_die "state binding is missing: $_hmlt_id"
                    printf '%s' "$(hw_state_target_link "$_hmlt_id")"
                    ;;
                direct) printf '%s' "$_hmlt_id" ;;
                *) hw_die "unknown state link kind: $_hmlt_kind" ;;
            esac
            ;;
        *) hw_die "unknown managed link type: $_hmlt_type" ;;
    esac
}

hw_managed_find_by_dest() {
    _hmfd_root=$1; _hmfd_dest=$2
    [ -d "$_hmfd_root" ] || return 1
    for _hmfd_entry in "$_hmfd_root"/*; do
        [ -d "$_hmfd_entry" ] || continue
        [ "$(cat "$_hmfd_entry/dest" 2>/dev/null)" = "$_hmfd_dest" ] && { printf '%s' "$_hmfd_entry"; return 0; }
    done
    return 1
}

# Validate and normalize all destinations before activation changes anything.
hw_managed_link_validate() {
    _hmlv_old=$1; _hmlv_new=$2
    _hmlv_old_root=$(hw_managed_links_dir "$_hmlv_old")
    _hmlv_new_root=$(hw_managed_links_dir "$_hmlv_new")
    [ -d "$_hmlv_new_root" ] || return 0
    hw_schema_check "$_hmlv_new_root" false
    for _hmlv_entry in "$_hmlv_new_root"/*; do
        [ -d "$_hmlv_entry" ] || continue
        _hmlv_dest=$(cat "$_hmlv_entry/dest")
        _hmlv_target=$(hw_managed_link_target "$_hmlv_entry") || hw_die "cannot resolve managed link target"
        _hmlv_expected=$(cat "$_hmlv_entry/expected-type" 2>/dev/null)
        if [ -n "$_hmlv_expected" ]; then
            if [ -d "$_hmlv_target" ]; then _hmlv_actual=directory; else _hmlv_actual=file; fi
            [ "$_hmlv_expected" = "$_hmlv_actual" ] || hw_die "managed state target type changed: $_hmlv_dest"
        fi
        # Conflicting declarations in the new generation are not allowed.
        for _hmlv_other in "$_hmlv_new_root"/*; do
            [ -d "$_hmlv_other" ] || continue
            [ "$_hmlv_other" = "$_hmlv_entry" ] && continue
            [ "$(cat "$_hmlv_other/dest")" = "$_hmlv_dest" ] || continue
            _hmlv_other_target=$(hw_managed_link_target "$_hmlv_other") || hw_die "cannot resolve managed link target"
            [ "$_hmlv_other_target" = "$_hmlv_target" ] || hw_die "managed link conflict at $_hmlv_dest"
        done
        hw_managed_link_is_nested "$_hmlv_entry" && continue
        if [ -e "$_hmlv_dest" ] && [ ! -L "$_hmlv_dest" ]; then
            hw_die "managed link destination is an unmanaged file or directory: $_hmlv_dest"
        fi
        if [ -L "$_hmlv_dest" ]; then
            _hmlv_existing=$(readlink "$_hmlv_dest")
            _hmlv_old_entry=$(hw_managed_find_by_dest "$_hmlv_old_root" "$_hmlv_dest" 2>/dev/null || printf '')
            if [ -z "$_hmlv_old_entry" ]; then
                [ "$_hmlv_existing" = "$_hmlv_target" ] || hw_die "managed link destination points to an unmanaged target: $_hmlv_dest"
            else
                _hmlv_old_target=$(hw_managed_link_target "$_hmlv_old_entry") || hw_die "cannot resolve previous managed link target"
                _hmlv_legacy_target=''
                if [ "$(cat "$_hmlv_old_entry/type" 2>/dev/null)" = state ] && \
                   [ "$(cat "$_hmlv_old_entry/kind" 2>/dev/null)" = named ]; then
                    _hmlv_legacy_target=$(hw_state_bind_read "$(cat "$_hmlv_old_entry/id")" 2>/dev/null || printf '')
                fi
                [ "$_hmlv_existing" = "$_hmlv_old_target" ] || \
                [ "$_hmlv_existing" = "$_hmlv_target" ] || \
                { [ -n "$_hmlv_legacy_target" ] && [ "$_hmlv_existing" = "$_hmlv_legacy_target" ]; } \
                    || hw_die "managed link was modified outside Homeworld: $_hmlv_dest"
            fi
        fi
    done
}

hw_managed_link_apply_locked() {
    _hmla_old=$1; _hmla_new=$2
    _hmla_old_root=$(hw_managed_links_dir "$_hmla_old")
    _hmla_new_root=$(hw_managed_links_dir "$_hmla_new")
    _hmla_n=1

    # Record every destination that may change.
    if [ -d "$_hmla_new_root" ]; then
        for _hmla_entry in "$_hmla_new_root"/*; do
            [ -d "$_hmla_entry" ] || continue
            hw_managed_link_is_nested "$_hmla_entry" && continue
            _hmla_dest=$(cat "$_hmla_entry/dest")
            _hmla_target=$(hw_managed_link_target "$_hmla_entry") || return 1
            _hmla_key=$(printf '%06d' "$_hmla_n")
            hw_transaction_record "$_hmla_key" replace "$_hmla_dest" "$_hmla_target"
            _hmla_n=$((_hmla_n + 1))
        done
    fi
    if [ -d "$_hmla_old_root" ]; then
        for _hmla_entry in "$_hmla_old_root"/*; do
            [ -d "$_hmla_entry" ] || continue
            hw_managed_link_is_nested "$_hmla_entry" && continue
            _hmla_dest=$(cat "$_hmla_entry/dest")
            hw_managed_find_by_dest "$_hmla_new_root" "$_hmla_dest" >/dev/null 2>&1 && continue
            _hmla_key=$(printf '%06d' "$_hmla_n")
            hw_transaction_record "$_hmla_key" remove "$_hmla_dest" ''
            _hmla_n=$((_hmla_n + 1))
        done
    fi

    # Create or replace desired links.
    if [ -d "$_hmla_new_root" ]; then
        for _hmla_entry in "$_hmla_new_root"/*; do
            [ -d "$_hmla_entry" ] || continue
            hw_managed_link_is_nested "$_hmla_entry" && continue
            _hmla_dest=$(cat "$_hmla_entry/dest")
            _hmla_target=$(hw_managed_link_target "$_hmla_entry") || return 1
            hw_symlink_replace "$_hmla_target" "$_hmla_dest" || return 1
            hw_test_interrupt after-binding-replace
        done
    fi

    # Remove destinations dropped by the new generation, but only if untouched.
    if [ -d "$_hmla_old_root" ]; then
        for _hmla_entry in "$_hmla_old_root"/*; do
            [ -d "$_hmla_entry" ] || continue
            hw_managed_link_is_nested "$_hmla_entry" && continue
            _hmla_dest=$(cat "$_hmla_entry/dest")
            hw_managed_find_by_dest "$_hmla_new_root" "$_hmla_dest" >/dev/null 2>&1 && continue
            _hmla_old_target=$(hw_managed_link_target "$_hmla_entry") || return 1
            if [ -L "$_hmla_dest" ] && [ "$(readlink "$_hmla_dest")" = "$_hmla_old_target" ]; then rm -f "$_hmla_dest"; fi
        done
    fi
}
