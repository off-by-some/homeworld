#!/bin/sh
# state.sh — machine-local state names and automatic active-link rebinding.

hw_state_name_dir() {
    printf '%s/%s' "$(hw_state_bindings_dir)" "$1"
}

# Named state is exposed through a stable machine-local resolver. Generations
# refer to this path, so changing a binding never rewrites retained generations.
hw_state_target_link() {
    printf '%s/%s' "$(hw_state_targets_dir)" "$1"
}

hw_state_validate_target() {
    _hsvt_target=$1
    hw_reject_line_breaks "$_hsvt_target" "state target"
    case "$_hsvt_target" in /*) : ;; *) hw_die "state target must be an absolute path: $_hsvt_target" ;; esac
    [ -e "$_hsvt_target" ] || [ -L "$_hsvt_target" ] \
        || hw_die "state target does not exist: $_hsvt_target"
    if [ -d "$_hsvt_target" ]; then printf directory; else printf file; fi
}

hw_state_bind_read() {
    _hsbr_name=$1
    hw_validate_name "$_hsbr_name" "state name"
    _hsbr_dir=$(hw_state_name_dir "$_hsbr_name")
    [ -d "$_hsbr_dir" ] || return 1
    hw_schema_check "$_hsbr_dir" false
    cat "$_hsbr_dir/path"
}

hw_state_bind_type() {
    _hsbt_dir=$(hw_state_name_dir "$1")
    [ -f "$_hsbt_dir/expected-type" ] || return 1
    cat "$_hsbt_dir/expected-type"
}

hw_state_bind_write_locked() {
    _hsbw_name=$1
    _hsbw_path=$2
    _hsbw_type=$3
    _hsbw_dir=$(hw_state_name_dir "$_hsbw_name")
    _hsbw_tmp="${_hsbw_dir}.tmp-$$"
    rm -rf "$_hsbw_tmp"
    mkdir -p "$_hsbw_tmp" "$(hw_state_targets_dir)" || hw_die "cannot create state binding metadata"
    hw_schema_write "$_hsbw_tmp"
    hw_atomic_write "$_hsbw_tmp/path" "$_hsbw_path"
    hw_atomic_write "$_hsbw_tmp/expected-type" "$_hsbw_type"
    rm -rf "${_hsbw_dir}.old-$$"
    [ ! -e "$_hsbw_dir" ] || mv "$_hsbw_dir" "${_hsbw_dir}.old-$$"
    mv "$_hsbw_tmp" "$_hsbw_dir" || {
        [ ! -e "${_hsbw_dir}.old-$$" ] || mv "${_hsbw_dir}.old-$$" "$_hsbw_dir"
        hw_die "cannot publish state binding"
    }
    if ! hw_symlink_replace "$_hsbw_path" "$(hw_state_target_link "$_hsbw_name")"; then
        rm -rf "$_hsbw_dir"
        [ ! -e "${_hsbw_dir}.old-$$" ] || mv "${_hsbw_dir}.old-$$" "$_hsbw_dir"
        hw_die "cannot publish state target"
    fi
    rm -rf "${_hsbw_dir}.old-$$"
}

# State storage must not live at or below a managed external root. Such a path
# would be hidden when that root becomes a Homeworld symlink and can otherwise
# create a circular relationship between deployment content and persistent data.
hw_state_target_conflicts_with_generation() {
    _hstcg_target=$1
    _hstcg_gen=$2
    _hstcg_root="$_hstcg_gen/.homeworld/managed-links"
    [ -d "$_hstcg_root" ] || return 1
    for _hstcg_entry in "$_hstcg_root"/*; do
        [ -d "$_hstcg_entry" ] || continue
        case "$(cat "$_hstcg_entry/type" 2>/dev/null)" in
            config|asset|repo)
                _hstcg_dest=$(cat "$_hstcg_entry/dest" 2>/dev/null) || continue
                hw_path_is_same_or_below "$_hstcg_target" "$_hstcg_dest" && return 0
                ;;
        esac
    done
    return 1
}

# Update a state name and migrate any old direct active links to the stable
# resolver. New generations and composed views already point to the resolver.
hw_state_bind_update() {
    _hsbu_name=$1
    _hsbu_path=$2
    hw_validate_name "$_hsbu_name" "state name"
    _hsbu_type=$(hw_state_validate_target "$_hsbu_path") || hw_die "state target is invalid"
    _hsbu_lock=$(hw_global_lock_dir)
    hw_lock_acquire "$_hsbu_lock" "state rebinding"
    hw_transaction_repair_locked

    _hsbu_active=''
    [ -L "$(hw_current)" ] && _hsbu_active=$(readlink "$(hw_current)")
    if [ -n "$_hsbu_active" ] && hw_state_target_conflicts_with_generation "$_hsbu_path" "$_hsbu_active"; then
        hw_lock_release "$_hsbu_lock"
        hw_die "state target is inside a managed external destination"
    fi

    _hsbu_consumers=$(mktemp)
    : > "$_hsbu_consumers"
    if [ -n "$_hsbu_active" ] && [ -d "$_hsbu_active/.homeworld/managed-links" ]; then
        for _hsbu_entry in "$_hsbu_active/.homeworld/managed-links"/*; do
            [ -d "$_hsbu_entry" ] || continue
            [ "$(cat "$_hsbu_entry/type" 2>/dev/null)" = state ] || continue
            [ "$(cat "$_hsbu_entry/kind" 2>/dev/null)" = named ] || continue
            [ "$(cat "$_hsbu_entry/id" 2>/dev/null)" = "$_hsbu_name" ] || continue
            _hsbu_expected=$(cat "$_hsbu_entry/expected-type" 2>/dev/null)
            [ "$_hsbu_expected" = "$_hsbu_type" ] || {
                rm -f "$_hsbu_consumers"; hw_lock_release "$_hsbu_lock"
                hw_die "state binding type changed for $_hsbu_name"
            }
            # Nested destinations are part of a generation-local composed view.
            [ -f "$_hsbu_entry/nested-under" ] && continue
            cat "$_hsbu_entry/dest" >> "$_hsbu_consumers"
            printf '\n' >> "$_hsbu_consumers"
        done
    fi

    while IFS= read -r _hsbu_dest; do
        [ -n "$_hsbu_dest" ] || continue
        if [ -e "$_hsbu_dest" ] && [ ! -L "$_hsbu_dest" ]; then
            rm -f "$_hsbu_consumers"; hw_lock_release "$_hsbu_lock"
            hw_die "state destination is no longer a symlink: $_hsbu_dest"
        fi
    done < "$_hsbu_consumers"

    _hsbu_old_path=''; _hsbu_old_type=''; _hsbu_old_exists=false
    if _hsbu_old_path=$(hw_state_bind_read "$_hsbu_name" 2>/dev/null); then
        _hsbu_old_exists=true
        _hsbu_old_type=$(hw_state_bind_type "$_hsbu_name" 2>/dev/null || printf '')
    fi

    hw_transaction_begin "${_hsbu_active:-state-rebind}"
    trap 'hw_transaction_present && hw_transaction_repair_locked; hw_lock_release "$_hsbu_lock"' EXIT
    trap 'hw_transaction_present && hw_transaction_repair_locked; hw_lock_release "$_hsbu_lock"; exit 143' HUP INT TERM
    hw_atomic_write "$(hw_transaction_dir)/state-binding-name" "$_hsbu_name"
    hw_atomic_write "$(hw_transaction_dir)/state-binding-existed" "$_hsbu_old_exists"
    hw_atomic_write "$(hw_transaction_dir)/state-binding-old-path" "$_hsbu_old_path"
    hw_atomic_write "$(hw_transaction_dir)/state-binding-old-type" "$_hsbu_old_type"

    _hsbu_resolver=$(hw_state_target_link "$_hsbu_name")
    hw_transaction_record 000000 replace "$_hsbu_resolver" "$_hsbu_path"
    _hsbu_n=1
    while IFS= read -r _hsbu_dest; do
        [ -n "$_hsbu_dest" ] || continue
        _hsbu_key=$(printf '%06d' "$_hsbu_n")
        hw_transaction_record "$_hsbu_key" replace "$_hsbu_dest" "$_hsbu_resolver"
        _hsbu_n=$((_hsbu_n + 1))
    done < "$_hsbu_consumers"

    hw_state_bind_write_locked "$_hsbu_name" "$_hsbu_path" "$_hsbu_type"
    while IFS= read -r _hsbu_dest; do
        [ -n "$_hsbu_dest" ] || continue
        hw_symlink_replace "$_hsbu_resolver" "$_hsbu_dest" || hw_die "could not update state destination: $_hsbu_dest"
    done < "$_hsbu_consumers"

    hw_transaction_finish
    rm -f "$_hsbu_consumers"
    hw_lock_release "$_hsbu_lock"
    trap - EXIT
    trap - HUP INT TERM
}

hw_state_resolve() {
    _hsr_value=$1
    case "$_hsr_value" in
        /*) printf '%s' "$_hsr_value" ;;
        *) hw_state_bind_read "$_hsr_value" || hw_die "unknown state binding: $_hsr_value" ;;
    esac
}
