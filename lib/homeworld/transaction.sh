#!/bin/sh
# transaction.sh — recoverable generation-pointer and external-link changes.
#
# The journal protects against process interruption and ordinary shell failure.
# Portable shell cannot promise durability across sudden power loss because it
# has no portable fsync primitive. Metadata is nevertheless written beside its
# destination and renamed before filesystem mutations begin.

hw_transaction_present() {
    [ -d "$(hw_transaction_dir)" ]
}

hw_transaction_operation_dir() {
    printf '%s/operations/%s' "$(hw_transaction_dir)" "$1"
}

hw_transaction_begin() {
    _htb_target=$1
    _htb_dir=$(hw_transaction_dir)
    [ ! -e "$_htb_dir" ] || hw_die "an activation transaction is already in progress"
    _htb_tmp="${_htb_dir}.tmp-$$"
    rm -rf "$_htb_tmp"
    mkdir -p "$_htb_tmp/operations" || hw_die "cannot create activation journal"
    hw_schema_write "$_htb_tmp"
    hw_atomic_write "$_htb_tmp/phase" prepared
    hw_atomic_write "$_htb_tmp/target-generation" "$_htb_target"
    hw_atomic_write "$_htb_tmp/old-current" "$(hw_readlink_or_empty "$(hw_current)")"
    hw_atomic_write "$_htb_tmp/old-previous" "$(hw_readlink_or_empty "$(hw_previous)")"
    mv "$_htb_tmp" "$_htb_dir" || { rm -rf "$_htb_tmp"; hw_die "cannot publish activation journal"; }
}

# Record the previous state of one destination before it is touched.
hw_transaction_record() {
    _htr_number=$1
    _htr_action=$2
    _htr_dest=$3
    _htr_new_target=${4:-}
    _htr_dir=$(hw_transaction_operation_dir "$_htr_number")
    mkdir -p "$_htr_dir" || hw_die "cannot extend activation journal"
    hw_atomic_write "$_htr_dir/action" "$_htr_action"
    hw_atomic_write "$_htr_dir/destination" "$_htr_dest"
    hw_atomic_write "$_htr_dir/new-target" "$_htr_new_target"
    if [ -L "$_htr_dest" ]; then
        hw_atomic_write "$_htr_dir/old-kind" symlink
        hw_atomic_write "$_htr_dir/old-target" "$(readlink "$_htr_dest")"
    else
        hw_atomic_write "$_htr_dir/old-kind" missing
        hw_atomic_write "$_htr_dir/old-target" ''
    fi
}

hw_transaction_phase() {
    hw_atomic_write "$(hw_transaction_dir)/phase" "$1" \
        || hw_die "cannot update activation journal phase"
}

hw_transaction_finish() {
    _htf_dir=$(hw_transaction_dir)
    [ -d "$_htf_dir" ] || return 0
    hw_transaction_phase complete
    rm -rf "$_htf_dir"
}

# Restore a destination from its recorded pre-transaction state.
hw_transaction_restore_operation() {
    _htro_dir=$1
    [ -d "$_htro_dir" ] || return 0
    _htro_dest=$(cat "$_htro_dir/destination" 2>/dev/null) || return 1
    _htro_kind=$(cat "$_htro_dir/old-kind" 2>/dev/null) || return 1
    case "$_htro_kind" in
        missing)
            [ -L "$_htro_dest" ] && rm -f "$_htro_dest"
            ;;
        symlink)
            _htro_target=$(cat "$_htro_dir/old-target" 2>/dev/null) || return 1
            hw_symlink_replace "$_htro_target" "$_htro_dest" || return 1
            ;;
        *) return 1 ;;
    esac
}

hw_transaction_repair_locked() {
    _htrl_dir=$(hw_transaction_dir)
    [ -d "$_htrl_dir" ] || return 0
    hw_schema_check "$_htrl_dir" false
    hw_warn "recovering an interrupted Homeworld transaction"

    # Restore external paths in reverse lexical order. Entry names are padded.
    if [ -d "$_htrl_dir/operations" ]; then
        find "$_htrl_dir/operations" -type d ! -path "$_htrl_dir/operations" -prune 2>/dev/null \
            | sort -r | while IFS= read -r _htrl_op; do
                hw_transaction_restore_operation "$_htrl_op" || exit 1
            done || hw_die "could not restore an interrupted binding transaction"
    fi

    if [ -f "$_htrl_dir/state-binding-name" ]; then
        _htrl_state_name=$(cat "$_htrl_dir/state-binding-name")
        _htrl_state_existed=$(cat "$_htrl_dir/state-binding-existed" 2>/dev/null || printf false)
        if [ "$_htrl_state_existed" = true ]; then
            _htrl_state_path=$(cat "$_htrl_dir/state-binding-old-path")
            _htrl_state_type=$(cat "$_htrl_dir/state-binding-old-type")
            hw_state_bind_write_locked "$_htrl_state_name" "$_htrl_state_path" "$_htrl_state_type"
        else
            rm -rf "$(hw_state_name_dir "$_htrl_state_name")"
            rm -f "$(hw_state_target_link "$_htrl_state_name")"
        fi
    fi

    _htrl_current=$(cat "$_htrl_dir/old-current" 2>/dev/null || printf '')
    _htrl_previous=$(cat "$_htrl_dir/old-previous" 2>/dev/null || printf '')
    if [ -n "$_htrl_current" ]; then
        hw_symlink_replace "$_htrl_current" "$(hw_current)" || hw_die "could not restore current generation"
    else
        rm -f "$(hw_current)"
    fi
    if [ -n "$_htrl_previous" ]; then
        hw_symlink_replace "$_htrl_previous" "$(hw_previous)" || hw_die "could not restore previous generation"
    else
        rm -f "$(hw_previous)"
    fi
    rm -rf "$_htrl_dir"
}

hw_transaction_repair() {
    hw_transaction_present || return 0
    _htr_lock=$(hw_global_lock_dir)
    hw_lock_acquire "$_htr_lock" "generation transaction"
    trap 'hw_lock_release "$_htr_lock"' EXIT HUP INT TERM
    hw_transaction_repair_locked
    hw_lock_release "$_htr_lock"
    trap - EXIT HUP INT TERM
}
