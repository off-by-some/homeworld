#!/bin/sh
# config.sh — generation resources and managed external bindings.

hw_managed_links_dir() { printf '%s/.homeworld/managed-links' "$1"; }
hw_projection_roots_dir() { printf '%s/.homeworld/projection-roots' "$1"; }
hw_resource_projections_dir() { printf '%s/.homeworld/resource-projections' "$1"; }

hw_projection_invalidate() {
    rm -rf "$1/.homeworld/projections-prepared"
}

hw_projection_write() {
    _hpw_path=$1
    _hpw_value=$2
    rm -rf "$_hpw_path"
    mkdir -p "$(dirname "$_hpw_path")" || hw_die "cannot write projection metadata"
    hw_write_bytes "$_hpw_path" "$_hpw_value" || hw_die "cannot write projection metadata"
}

hw_metadata_id() {
    _hmi_value=$1
    if command -v git >/dev/null 2>&1; then env printf '%s' "$_hmi_value" | git hash-object --stdin; else env printf '%s' "$_hmi_value" | cksum | awk '{print $1}'; fi
}

hw_copy_resource() {
    _hcr_source=$1
    _hcr_dest=$2
    [ ! -L "$_hcr_source" ] || hw_die "resource source is a symlink; resolve the link before staging"
    [ -e "$_hcr_source" ] || hw_die "resource source does not exist: $_hcr_source"
    _hcr_parent=$(dirname "$_hcr_dest")
    _hcr_tmp="$_hcr_parent/.tmp-$(basename "$_hcr_dest").$$"
    mkdir -p "$_hcr_parent"
    hw_tree_make_removable "$_hcr_tmp"
    rm -rf "$_hcr_tmp"
    if [ -d "$_hcr_source" ]; then
        mkdir -p "$_hcr_tmp"
        cp -R "$_hcr_source/." "$_hcr_tmp/" || { rm -rf "$_hcr_tmp"; hw_die "could not stage resource"; }
    else
        cp "$_hcr_source" "$_hcr_tmp" || { rm -f "$_hcr_tmp"; hw_die "could not stage resource"; }
    fi
    # Resources are generation-owned snapshots. They may be replaced while a
    # generation is still pending, but a completed resource should not behave
    # like a writable pointer back to the module workspace.
    chmod -R a-w "$_hcr_tmp" 2>/dev/null || true
    hw_tree_make_removable "$_hcr_dest"
    rm -rf "$_hcr_dest"
    mv "$_hcr_tmp" "$_hcr_dest" || hw_die "could not publish staged resource"
}

hw_config_add() {
    _hca_source=$1; _hca_name=$2; _hca_gen=$3; _hca_module=$4
    hw_validate_name "$_hca_name" "config name"
    case "$_hca_source" in /*) hw_die "config source must be relative to the module root" ;; esac
    _hca_root=${HOMEWORLD_MODULE_ROOT:-}
    [ -n "$_hca_root" ] || hw_die "config add can only be called during module installation"
    _hca_safe=$(hw_safe_path "$_hca_root" "$_hca_source") || hw_die "invalid config source path"
    hw_copy_resource "$_hca_safe" "$_hca_gen/config/$_hca_module/$_hca_name"
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
    hw_projection_invalidate "$_hmlr_gen"
}

hw_config_link() {
    _hcl_name=$1; _hcl_dest=$2; _hcl_module=$3; _hcl_gen=$4
    hw_validate_name "$_hcl_name" "config name"
    [ -e "$_hcl_gen/config/$_hcl_module/$_hcl_name" ] || \
        [ -L "$_hcl_gen/config/$_hcl_module/$_hcl_name" ] || \
        hw_die "config is not part of the pending generation: $_hcl_name"
    hw_managed_link_record "$_hcl_dest" config "$_hcl_module/$_hcl_name" "$_hcl_module" "$_hcl_gen"
}

hw_asset_link() {
    _hale_name=$1; _hale_dest=$2; _hale_gen=$3; _hale_module=$4
    hw_validate_name "$_hale_name" "asset name"
    [ -e "$_hale_gen/assets/$_hale_module/$_hale_name" ] || \
        [ -L "$_hale_gen/assets/$_hale_module/$_hale_name" ] || \
        hw_die "asset is not part of the pending generation: $_hale_name"
    hw_managed_link_record "$_hale_dest" asset "$_hale_module/$_hale_name" "$_hale_module" "$_hale_gen"
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

# Resolve the real filesystem target used inside a composed projection. This
# deliberately does not use hw_managed_link_target_for_gen because external
# config/asset/repo links point through current, while pending projections must
# be built from the generation being activated or inspected.
hw_managed_link_nested_target_source() {
    _hmlnts_entry=$1
    _hmlnts_gen=$2
    _hmlnts_type=$(cat "$_hmlnts_entry/type")
    _hmlnts_id=$(cat "$_hmlnts_entry/id")
    case "$_hmlnts_type" in
        config|asset)
            hw_managed_link_generation_source "$_hmlnts_entry" "$_hmlnts_gen"
            ;;
        state)
            _hmlnts_kind=$(cat "$_hmlnts_entry/kind")
            case "$_hmlnts_kind" in
                named) hw_state_target_link "$_hmlnts_id" ;;
                direct) printf '%s' "$_hmlnts_id" ;;
                *) hw_die "unknown state link kind: $_hmlnts_kind" ;;
            esac
            ;;
        *) hw_die "managed link type cannot be nested: $_hmlnts_type" ;;
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

hw_projection_insert() {
    _hpi_source=$1
    _hpi_view=$2
    _hpi_relative=$3
    _hpi_target=$4
    _hpi_policy=$5
    hw_reject_line_breaks "$_hpi_relative" "nested resource path"
    case "/$_hpi_relative/" in
        */../* | */./* | *//*) hw_die "nested resource destination contains an unsafe path component" ;;
    esac
    [ -n "$_hpi_relative" ] || hw_die "nested resource destination cannot replace its managed parent"

    _hpi_source_cursor=$_hpi_source
    _hpi_view_cursor=$_hpi_view
    _hpi_remaining=$_hpi_relative
    while :; do
        case "$_hpi_remaining" in
            */*)
                _hpi_component=${_hpi_remaining%%/*}
                _hpi_remaining=${_hpi_remaining#*/}
                _hpi_source_next="$_hpi_source_cursor/$_hpi_component"
                _hpi_view_next="$_hpi_view_cursor/$_hpi_component"
                if [ -e "$_hpi_source_next" ] || [ -L "$_hpi_source_next" ]; then
                    [ -d "$_hpi_source_next" ] && [ ! -L "$_hpi_source_next" ] \
                        || hw_die "nested resource destination crosses a non-directory path: $_hpi_relative"
                    if [ -L "$_hpi_view_next" ]; then
                        rm -f "$_hpi_view_next" || return 1
                        hw_projection_populate_dir "$_hpi_source_next" "$_hpi_view_next" || return 1
                    elif [ ! -d "$_hpi_view_next" ]; then
                        hw_die "nested resource destination conflicts with another projection: $_hpi_relative"
                    fi
                else
                    if [ -e "$_hpi_view_next" ] || [ -L "$_hpi_view_next" ]; then
                        [ -d "$_hpi_view_next" ] && [ ! -L "$_hpi_view_next" ] \
                            || hw_die "nested resource destination conflicts with another projection: $_hpi_relative"
                    else
                        mkdir -p "$_hpi_view_next" || return 1
                    fi
                fi
                _hpi_source_cursor=$_hpi_source_next
                _hpi_view_cursor=$_hpi_view_next
                ;;
            *)
                _hpi_source_final="$_hpi_source_cursor/$_hpi_remaining"
                _hpi_view_final="$_hpi_view_cursor/$_hpi_remaining"
                case "$_hpi_policy" in
                    state)
                        if [ -e "$_hpi_source_final" ] || [ -L "$_hpi_source_final" ]; then
                            hw_die "nested state destination conflicts with content supplied by the managed resource: $_hpi_relative"
                        fi
                        if [ -L "$_hpi_view_final" ] && [ "$(readlink "$_hpi_view_final")" = "$_hpi_target" ]; then
                            return 0
                        fi
                        if [ -e "$_hpi_view_final" ] || [ -L "$_hpi_view_final" ]; then
                            hw_die "nested state destination conflicts with another managed declaration: $_hpi_relative"
                        fi
                        ;;
                    replace)
                        # Immutable overlays may replace an existing file or
                        # directory from the base resource; ancestor/descendant
                        # overlay ambiguity is rejected before projections are
                        # realized.
                        hw_tree_make_removable "$_hpi_view_final"
                        rm -rf "$_hpi_view_final" 2>/dev/null || return 1
                        ;;
                    *) hw_die "unknown projection policy: $_hpi_policy" ;;
                esac
                hw_symlink_replace "$_hpi_target" "$_hpi_view_final" || return 1
                return 0
                ;;
        esac
    done
}

hw_projection_parent_record() {
    _hppr_gen=$1; _hppr_key=$2; _hppr_source=$3; _hppr_dest=$4; _hppr_type=$5; _hppr_id=$6; _hppr_scope=$7
    _hppr_dir=$(hw_projection_roots_dir "$_hppr_gen")/$_hppr_key
    rm -rf "$_hppr_dir"
    mkdir -p "$_hppr_dir" || hw_die "cannot record projection parent"
    hw_schema_write "$_hppr_dir"
    hw_atomic_write "$_hppr_dir/source" "$_hppr_source"
    hw_atomic_write "$_hppr_dir/dest" "$_hppr_dest"
    hw_atomic_write "$_hppr_dir/type" "$_hppr_type"
    hw_atomic_write "$_hppr_dir/id" "$_hppr_id"
    hw_atomic_write "$_hppr_dir/scope" "$_hppr_scope"
}


# Detect nested managed resources below immutable directory resources and
# realize them as generation-local composed views. Immutable config/asset
# overlays may replace repository content; mutable state may only occupy empty
# paths.
hw_managed_link_prepare_views() {
    _hmpv_gen=$1
    _hmpv_root=$(hw_managed_links_dir "$_hmpv_gen")
    _hmpv_marker="$_hmpv_gen/.homeworld/projections-prepared"
    [ -f "$_hmpv_marker" ] && return 0
    rm -rf "$_hmpv_marker"

    _hmpv_projection_root="$_hmpv_gen/.homeworld/projections"
    _hmpv_parent_root=$(hw_projection_roots_dir "$_hmpv_gen")
    _hmpv_resource_root=$(hw_resource_projections_dir "$_hmpv_gen")
    # Projections are frozen after construction, but repo path can be resolved
    # repeatedly while the generation is still pending. Make old views removable
    # before rebuilding the projection index.
    hw_tree_make_removable "$_hmpv_projection_root"
    hw_tree_make_removable "$_hmpv_parent_root"
    hw_tree_make_removable "$_hmpv_resource_root"
    rm -rf "$_hmpv_projection_root" "$_hmpv_parent_root" "$_hmpv_resource_root" \
        || hw_die "cannot reset managed resource projections"
    mkdir -p "$_hmpv_projection_root" "$_hmpv_parent_root" "$_hmpv_resource_root/repo" \
        || hw_die "cannot create managed resource projections"
    hw_schema_write "$_hmpv_projection_root"
    hw_schema_write "$_hmpv_parent_root"
    hw_schema_write "$_hmpv_resource_root"

    if [ -d "$_hmpv_root" ]; then
        hw_schema_check "$_hmpv_root" false
        for _hmpv_entry in "$_hmpv_root"/*; do
            [ -d "$_hmpv_entry" ] || continue
            rm -rf "$_hmpv_entry/projection" "$_hmpv_entry/nested-under" "$_hmpv_entry/nested-path"
        done

        for _hmpv_parent in "$_hmpv_root"/*; do
            [ -d "$_hmpv_parent" ] || continue
            case "$(cat "$_hmpv_parent/type" 2>/dev/null)" in config|asset|repo) : ;; *) continue ;; esac
            _hmpv_parent_source=$(hw_managed_link_generation_source "$_hmpv_parent" "$_hmpv_gen") || continue
            [ -d "$_hmpv_parent_source" ] || continue
            _hmpv_parent_dest=$(cat "$_hmpv_parent/dest")
            _hmpv_parent_key=${_hmpv_parent##*/}
            _hmpv_parent_type=$(cat "$_hmpv_parent/type")
            _hmpv_parent_id=$(cat "$_hmpv_parent/id")
            hw_projection_parent_record "$_hmpv_gen" "$_hmpv_parent_key" "$_hmpv_parent_source" \
                "$_hmpv_parent_dest" "$_hmpv_parent_type" "$_hmpv_parent_id" external
        done
    fi

    # Repositories are immutable directory resources even before they are linked
    # to an external destination. This lets modules compose asset overlays into
    # `homeworld repo path <name>` and use the composed view during install.
    for _hmpv_repo in "$_hmpv_gen/repos"/*; do
        [ -e "$_hmpv_repo" ] || [ -L "$_hmpv_repo" ] || continue
        [ -d "$_hmpv_repo" ] || continue
        _hmpv_repo_ns=${_hmpv_repo##*/}
        _hmpv_repo_key=$(hw_metadata_id "internal|repo|$_hmpv_repo_ns")
        hw_projection_parent_record "$_hmpv_gen" "$_hmpv_repo_key" "$_hmpv_repo" \
            "$_hmpv_repo" repo "$_hmpv_repo_ns" internal
    done

    [ -d "$_hmpv_root" ] || { rm -rf "$_hmpv_marker"; hw_projection_write "$_hmpv_marker" yes; return 0; }

    # First reject state storage that would itself be hidden by a managed
    # immutable directory, whether that directory is external or generation-local.
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
        for _hmpv_parent in "$_hmpv_parent_root"/*; do
            [ -d "$_hmpv_parent" ] || continue
            _hmpv_parent_dest=$(cat "$_hmpv_parent/dest")
            hw_path_is_same_or_below "$_hmpv_state_target" "$_hmpv_parent_dest" \
                && hw_die "state target is inside a managed destination: $_hmpv_state_target"
        done
    done

    # Attach each nested immutable resource or state declaration to its nearest
    # immutable directory parent. Declarations without such a parent remain
    # external links.
    for _hmpv_child in "$_hmpv_root"/*; do
        [ -d "$_hmpv_child" ] || continue
        _hmpv_child_type=$(cat "$_hmpv_child/type" 2>/dev/null)
        case "$_hmpv_child_type" in config|asset|state) : ;; *) continue ;; esac
        _hmpv_child_dest=$(cat "$_hmpv_child/dest")
        _hmpv_best=''; _hmpv_best_dest=''; _hmpv_best_length=0
        for _hmpv_parent in "$_hmpv_parent_root"/*; do
            [ -d "$_hmpv_parent" ] || continue
            _hmpv_parent_dest=$(cat "$_hmpv_parent/dest")
            hw_path_is_below "$_hmpv_child_dest" "$_hmpv_parent_dest" || continue
            _hmpv_length=${#_hmpv_parent_dest}
            if [ "$_hmpv_length" -gt "$_hmpv_best_length" ]; then
                _hmpv_best=$_hmpv_parent
                _hmpv_best_dest=$_hmpv_parent_dest
                _hmpv_best_length=$_hmpv_length
            fi
        done
        [ -n "$_hmpv_best" ] || continue
        _hmpv_key=${_hmpv_best##*/}
        _hmpv_relative=${_hmpv_child_dest#"$_hmpv_best_dest"/}
        rm -rf "$_hmpv_child/nested-under" "$_hmpv_child/nested-path"
        hw_projection_write "$_hmpv_child/nested-under" "$_hmpv_key"
        hw_projection_write "$_hmpv_child/nested-path" "$_hmpv_relative"
        rm -rf "$_hmpv_best/needs-projection"
        hw_projection_write "$_hmpv_best/needs-projection" yes
        _hmpv_scope=$(cat "$_hmpv_best/scope")
        if [ "$_hmpv_scope" = external ]; then
            rm -rf "$_hmpv_root/$_hmpv_key/projection"
            hw_projection_write "$_hmpv_root/$_hmpv_key/projection" "$_hmpv_key"
        else
            _hmpv_type=$(cat "$_hmpv_best/type")
            _hmpv_id=$(cat "$_hmpv_best/id")
            mkdir -p "$_hmpv_resource_root/$_hmpv_type"
            hw_projection_write "$_hmpv_resource_root/$_hmpv_type/$_hmpv_id" "$_hmpv_key"
        fi
    done

    # Reject ambiguous nested declarations under the same parent. Exact duplicate
    # destinations are allowed only when they resolve to the same target;
    # ancestor overlaps are not layered implicitly.
    for _hmpv_one in "$_hmpv_root"/*; do
        [ -d "$_hmpv_one" ] || continue
        [ -f "$_hmpv_one/nested-under" ] || continue
        _hmpv_one_parent=$(cat "$_hmpv_one/nested-under")
        _hmpv_one_path=$(cat "$_hmpv_one/nested-path")
        for _hmpv_two in "$_hmpv_root"/*; do
            [ -d "$_hmpv_two" ] || continue
            [ "$_hmpv_two" = "$_hmpv_one" ] && continue
            [ "$(cat "$_hmpv_two/nested-under" 2>/dev/null)" = "$_hmpv_one_parent" ] || continue
            _hmpv_two_path=$(cat "$_hmpv_two/nested-path")
            if [ "$_hmpv_one_path" = "$_hmpv_two_path" ]; then
                _hmpv_one_target=$(hw_managed_link_nested_target_source "$_hmpv_one" "$_hmpv_gen") \
                    || hw_die "cannot resolve nested managed declaration"
                _hmpv_two_target=$(hw_managed_link_nested_target_source "$_hmpv_two" "$_hmpv_gen") \
                    || hw_die "cannot resolve nested managed declaration"
                [ "$_hmpv_one_target" = "$_hmpv_two_target" ] && continue
                hw_die "nested managed declarations conflict at: $_hmpv_one_path"
            fi
            if hw_path_is_same_or_below "$_hmpv_one_path" "$_hmpv_two_path" || \
               hw_path_is_same_or_below "$_hmpv_two_path" "$_hmpv_one_path"; then
                hw_die "nested managed declarations overlap: $_hmpv_one_path"
            fi
        done
    done

    # Realize each projection after all nested declarations are known.
    for _hmpv_parent in "$_hmpv_parent_root"/*; do
        [ -d "$_hmpv_parent" ] || continue
        [ -f "$_hmpv_parent/needs-projection" ] || continue
        _hmpv_key=${_hmpv_parent##*/}
        _hmpv_source=$(cat "$_hmpv_parent/source")
        [ -d "$_hmpv_source" ] || hw_die "projection requires a managed directory resource"
        _hmpv_source=$(cd -P "$_hmpv_source" 2>/dev/null && pwd) \
            || hw_die "cannot resolve managed projection source"
        _hmpv_view="$_hmpv_projection_root/$_hmpv_key"
        hw_projection_populate_dir "$_hmpv_source" "$_hmpv_view" \
            || hw_die "cannot build managed resource projection"
        for _hmpv_child in "$_hmpv_root"/*; do
            [ -d "$_hmpv_child" ] || continue
            [ "$(cat "$_hmpv_child/nested-under" 2>/dev/null)" = "$_hmpv_key" ] || continue
            _hmpv_child_type=$(cat "$_hmpv_child/type")
            _hmpv_id=$(cat "$_hmpv_child/id")
            case "$_hmpv_child_type" in
                state)
                    _hmpv_target=$(hw_managed_link_nested_target_source "$_hmpv_child" "$_hmpv_gen") \
                        || hw_die "cannot resolve nested state source"
                    _hmpv_policy=state
                    ;;
                config|asset)
                    _hmpv_target=$(hw_managed_link_nested_target_source "$_hmpv_child" "$_hmpv_gen") \
                        || hw_die "cannot resolve nested $_hmpv_child_type source"
                    _hmpv_policy=replace
                    ;;
                *) hw_die "unknown nested managed link type: $_hmpv_child_type" ;;
            esac
            _hmpv_relative=$(cat "$_hmpv_child/nested-path")
            hw_projection_insert "$_hmpv_source" "$_hmpv_view" "$_hmpv_relative" "$_hmpv_target" "$_hmpv_policy" \
                || hw_die "cannot insert nested $_hmpv_child_type into managed resource projection"
        done
        find "$_hmpv_view" -type d -exec chmod a-w {} + 2>/dev/null || true
    done

    rm -rf "$_hmpv_marker"
    hw_projection_write "$_hmpv_marker" yes
}

hw_managed_link_target_for_gen() {
    _hmlt_entry=$1
    _hmlt_gen=$2
    _hmlt_type=$(cat "$_hmlt_entry/type")
    _hmlt_id=$(cat "$_hmlt_entry/id")
    case "$_hmlt_type" in
        config|asset|repo)
            # External managed links intentionally point through the stable
            # current-generation symlink. That lets rollback retarget them by
            # moving one pointer instead of rewriting every destination.
            _hmlt_base=$(hw_current)
            if [ -f "$_hmlt_entry/projection" ]; then
                printf '%s/.homeworld/projections/%s' "$_hmlt_base" "$(cat "$_hmlt_entry/projection")"
            else
                case "$_hmlt_type" in
                    config) printf '%s/config/%s' "$_hmlt_base" "$_hmlt_id" ;;
                    asset) printf '%s/assets/%s' "$_hmlt_base" "$_hmlt_id" ;;
                    repo) printf '%s/repos/%s' "$_hmlt_base" "$_hmlt_id" ;;
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

hw_managed_link_target() {
    hw_managed_link_target_for_gen "$1" "$(hw_current)"
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
        _hmlv_target=$(hw_managed_link_target_for_gen "$_hmlv_entry" "$_hmlv_new") || hw_die "cannot resolve managed link target"
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
            _hmlv_other_target=$(hw_managed_link_target_for_gen "$_hmlv_other" "$_hmlv_new") || hw_die "cannot resolve managed link target"
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
                _hmlv_old_target=$(hw_managed_link_target_for_gen "$_hmlv_old_entry" "$_hmlv_old") || hw_die "cannot resolve previous managed link target"
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
            _hmla_target=$(hw_managed_link_target_for_gen "$_hmla_entry" "$_hmla_new") || return 1
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
            _hmla_target=$(hw_managed_link_target_for_gen "$_hmla_entry" "$_hmla_new") || return 1
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
            _hmla_old_target=$(hw_managed_link_target_for_gen "$_hmla_entry" "$_hmla_old") || return 1
            if [ -L "$_hmla_dest" ] && [ "$(readlink "$_hmla_dest")" = "$_hmla_old_target" ]; then rm -f "$_hmla_dest"; fi
        done
    fi
}
