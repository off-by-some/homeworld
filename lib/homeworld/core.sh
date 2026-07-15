#!/bin/sh
# core.sh — fundamental constants and utilities
# No side effects on load. Every other library depends on this one.

HW_VERSION="2.0.2"

# XDG-compliant runtime paths. These are stable across invocations and are
# never changed after initialization — callers that cache them are safe.
HW_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/homeworld"
HW_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/homeworld"
HW_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/homeworld"

# ---------------------------------------------------------------------------
# Color — an optional presentation layer, never load-bearing
# ---------------------------------------------------------------------------
# COLOR_MODE controls when ANSI colors are emitted:
#   auto   — only when stderr is a real terminal and NO_COLOR is not set
#   always — force color on (useful when piping through color-aware pagers)
#   never  — force color off
# The NO_COLOR convention (https://no-color.org) is always honoured in auto mode.

COLOR_MODE=${COLOR_MODE:-auto}

_hw_use_color=false
case "$COLOR_MODE" in
    always) _hw_use_color=true ;;
    never)  _hw_use_color=false ;;
    auto)
        if [ -t 2 ] && [ -z "${NO_COLOR+x}" ] && [ "${TERM:-dumb}" != dumb ]; then
            _hw_use_color=true
        fi
        ;;
    *)
        printf 'homeworld: invalid COLOR_MODE: %s\n' "$COLOR_MODE" >&2
        exit 2
        ;;
esac

# Semantic color variables — all empty when color is off, so every printf
# that interpolates them produces identical output in both modes. Color only
# appears on status tokens (OK, WARN, INSTALL, SKIP) and the error/warn labels
# in hw_die and hw_warn; it never decorates plain text or data values.
#
# We try tput first because it reads the terminal's terminfo database. If tput
# is missing or the terminal doesn't support enough colors, we fall back to
# hard-coded ANSI escapes, which work on virtually every modern terminal.
_HW_C_OK=''; _HW_C_WARN=''; _HW_C_ERR=''; _HW_C_BOLD=''; _HW_C_RST=''

if [ "$_hw_use_color" = true ]; then
    if command -v tput >/dev/null 2>&1 &&
       _hw_nc=$(tput colors 2>/dev/null) &&
       [ "${_hw_nc:-0}" -ge 8 ]; then
        _HW_C_OK=$(tput setaf 2)
        _HW_C_WARN=$(tput setaf 3)
        _HW_C_ERR=$(tput setaf 1)
        _HW_C_BOLD=$(tput bold)
        _HW_C_RST=$(tput sgr0)
    else
        # printf '\033' is the POSIX-portable way to get ESC; $'\033' is not.
        _hw_e=$(printf '\033')
        _HW_C_OK="${_hw_e}[32m"
        _HW_C_WARN="${_hw_e}[33m"
        _HW_C_ERR="${_hw_e}[31m"
        _HW_C_BOLD="${_hw_e}[1m"
        _HW_C_RST="${_hw_e}[0m"
        unset _hw_e
    fi
    unset _hw_nc
fi
unset _hw_use_color

# Export so subshells spawned by pipes (find|while) and child processes see
# the same values. Without this, hw_die inside a pipe subshell would print
# without color even when the parent has color enabled.
export _HW_C_OK _HW_C_WARN _HW_C_ERR _HW_C_BOLD _HW_C_RST

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

# hw_log — plain progress message to stderr. No prefix, no color.
# For color-coded status lines (OK, WARN, INSTALL, SKIP), callers build the
# printf directly so the color wraps only the token, not the whole line.
hw_log() {
    printf '%s\n' "$1" >&2
}

# hw_warn — non-fatal warning to stderr. The WARN token is colored yellow.
# Use when something is wrong but the operation can continue.
hw_warn() {
    printf 'homeworld: %sWARN%s  %s\n' "$_HW_C_WARN" "$_HW_C_RST" "$1" >&2
}

# hw_die — unrecoverable error. Prints a colored "error:" label and exits.
# The optional second argument is a one-line hint shown below the error so
# the user knows their next move before going to look anything up.
hw_die() {
    printf 'homeworld: %serror:%s %s\n' "$_HW_C_ERR" "$_HW_C_RST" "$1" >&2
    if [ $# -ge 2 ] && [ -n "$2" ]; then
        printf '\n' >&2
        printf 'hint: %s\n' "$2" >&2
    fi
    exit 1
}

# hw_current — the canonical path of the active generation symlink.
hw_current() {
    printf '%s/current' "$HW_DATA"
}

# hw_previous — the canonical path of the previous generation symlink.
hw_previous() {
    printf '%s/previous' "$HW_DATA"
}

# hw_safe_path — guard against path traversal. Rejects relative components
# (..) and paths that start with / — both could escape the intended root.
hw_safe_path() {
    _sp_base="$1"
    _sp_rel="$2"

    # Reject .. as a path *segment* (i.e. when it is the whole string, or is
    # delimited by slashes). A filename that merely *contains* two dots — like
    # "v1..2.cfg" — is fine. The four patterns cover every traversal form:
    #   ..          the whole path is just ".."
    #   ../*        starts with "../"
    #   */..        ends with "/.."
    #   */../*      has "/../" somewhere in the middle
    case "$_sp_rel" in
        /* | .. | ../* | */.. | */../*)
            hw_die "path traversal not allowed: $_sp_rel" ;;
    esac

    printf '%s/%s' "$_sp_base" "$_sp_rel"
}

# hw_require — fail early with a clear message when an external tool is missing,
# rather than producing a cryptic error when the command is actually needed.
hw_require() {
    command -v "$1" >/dev/null 2>&1 \
        || hw_die "required command not found: $1" \
                  "Install $1 and ensure it is on your PATH, then try again."
}

# ---------------------------------------------------------------------------
# Runtime paths and durable metadata helpers
# ---------------------------------------------------------------------------

HW_SCHEMA_VERSION=1
HW_MIRROR_GRACE_DAYS=${HW_MIRROR_GRACE_DAYS:-30}

hw_git_dir() { printf '%s/git' "$HW_DATA"; }
hw_mirrors_dir() { printf '%s/git/mirrors' "$HW_DATA"; }
hw_checkouts_dir() { printf '%s/git/checkouts' "$HW_DATA"; }
hw_orphaned_dir() { printf '%s/git/orphaned' "$HW_DATA"; }
hw_transaction_dir() { printf '%s/activation-journal' "$HW_STATE"; }
hw_state_bindings_dir() { printf '%s/state-bindings' "$HW_STATE"; }
hw_state_targets_dir() { printf '%s/state-targets' "$HW_STATE"; }
hw_global_lock_dir() { printf '%s/locks/generation.lock' "$HW_STATE"; }

# Metadata is line-oriented. Reject line breaks explicitly rather than
# accidentally accepting paths that a portable shell cannot round-trip safely.
hw_reject_line_breaks() {
    _hrl_value=$1
    _hrl_label=$2
    _hrl_carriage_return=$(printf '\r')
    case "$_hrl_value" in
        *"
"* | *"$_hrl_carriage_return"*) hw_die "$_hrl_label contains a line break" ;;
    esac
}

hw_path_is_same_or_below() {
    _hpis_child=$1
    _hpis_parent=$2
    [ "$_hpis_child" = / ] || _hpis_child=${_hpis_child%/}
    [ "$_hpis_parent" = / ] || _hpis_parent=${_hpis_parent%/}
    [ "$_hpis_child" = "$_hpis_parent" ] && return 0
    [ "$_hpis_parent" = / ] && return 0
    case "$_hpis_child" in "$_hpis_parent"/*) return 0 ;; *) return 1 ;; esac
}

hw_path_is_below() {
    [ "$1" != "$2" ] || return 1
    hw_path_is_same_or_below "$1" "$2"
}

hw_validate_name() {
    _hvn_value=$1
    _hvn_label=$2
    hw_reject_line_breaks "$_hvn_value" "$_hvn_label"
    case "$_hvn_value" in
        '' | -* | *[!a-z0-9._-]* | */* | . | ..)
            hw_die "invalid $_hvn_label: $_hvn_value" \
                   "Use lowercase letters, numbers, dots, underscores, or hyphens."
            ;;
    esac
}

# Atomic replacement for small metadata files. The temporary file is created
# beside the destination so the final rename never crosses a filesystem.
hw_atomic_write() {
    _haw_path=$1
    _haw_value=$2
    _haw_parent=$(dirname "$_haw_path")
    _haw_tmp="$_haw_parent/.tmp-$(basename "$_haw_path").$$"
    mkdir -p "$_haw_parent" || return 1
    _haw_old_umask=$(umask)
    umask 077
    if ! printf '%s' "$_haw_value" > "$_haw_tmp"; then
        umask "$_haw_old_umask"
        rm -f "$_haw_tmp"
        return 1
    fi
    if ! mv -f "$_haw_tmp" "$_haw_path"; then
        umask "$_haw_old_umask"
        rm -f "$_haw_tmp"
        return 1
    fi
    umask "$_haw_old_umask"
}

hw_schema_write() {
    hw_atomic_write "$1/schema-version" "$HW_SCHEMA_VERSION"
}

# Missing schema files are accepted only for legacy generation metadata.
hw_schema_check() {
    _hsc_dir=$1
    _hsc_legacy=${2:-false}
    if [ ! -f "$_hsc_dir/schema-version" ]; then
        [ "$_hsc_legacy" = true ] && return 0
        hw_die "metadata is incomplete: $_hsc_dir has no schema-version"
    fi
    _hsc_version=$(cat "$_hsc_dir/schema-version" 2>/dev/null) || hw_die "cannot read metadata schema: $_hsc_dir"
    [ "$_hsc_version" = "$HW_SCHEMA_VERSION" ] \
        || hw_die "unsupported metadata schema $_hsc_version in $_hsc_dir" \
                  "Update Homeworld before using metadata written by a newer version."
}

# A process fingerprint avoids treating a rapidly reused PID as the owner of an
# old directory lock. ps is portable; the exact timestamp format is opaque.
hw_process_fingerprint() {
    _hpf_pid=$1
    _hpf_started=$(ps -p "$_hpf_pid" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]][[:space:]]*/ /g')
    [ -n "$_hpf_started" ] || _hpf_started=unknown
    printf '%s|%s' "$_hpf_pid" "$_hpf_started"
}

hw_lock_acquire() {
    _hla_path=$1
    _hla_label=${2:-operation}
    _hla_wait=${HW_LOCK_WAIT_SECONDS:-30}
    _hla_elapsed=0
    mkdir -p "$(dirname "$_hla_path")"
    while ! mkdir "$_hla_path" 2>/dev/null; do
        _hla_owner=''
        [ -f "$_hla_path/owner" ] && _hla_owner=$(cat "$_hla_path/owner" 2>/dev/null)
        _hla_pid=${_hla_owner%%|*}
        _hla_live=false
        case "$_hla_pid" in
            '' | *[!0-9]*) : ;;
            *)
                if kill -0 "$_hla_pid" 2>/dev/null; then
                    _hla_now=$(hw_process_fingerprint "$_hla_pid")
                    [ "$_hla_now" = "$_hla_owner" ] && _hla_live=true
                fi
                ;;
        esac
        if [ "$_hla_live" = false ]; then
            rm -rf "$_hla_path" 2>/dev/null || true
            continue
        fi
        [ "$_hla_elapsed" -lt "$_hla_wait" ] \
            || hw_die "timed out waiting for $_hla_label"
        sleep 1
        _hla_elapsed=$((_hla_elapsed + 1))
    done
    hw_atomic_write "$_hla_path/owner" "$(hw_process_fingerprint $$)" \
        || { rm -rf "$_hla_path"; hw_die "could not record $_hla_label lock ownership"; }
}

hw_lock_release() {
    _hlr_path=$1
    [ -d "$_hlr_path" ] || return 0
    _hlr_owner=''
    [ -f "$_hlr_path/owner" ] && _hlr_owner=$(cat "$_hlr_path/owner" 2>/dev/null)
    [ "$_hlr_owner" = "$(hw_process_fingerprint $$)" ] || return 0
    rm -rf "$_hlr_path"
}

# Restore owner access on generated read-only directory views before removal.
# find does not follow symlinked directories, so referenced state and checkout
# content is never chmodded through a projection.
hw_tree_make_removable() {
    [ -d "$1" ] || return 0
    find "$1" -type d -exec chmod u+rwx {} + 2>/dev/null || true
}

# Replace a symlink name without following an existing directory symlink.
hw_symlink_replace() {
    _hsr_target=$1
    _hsr_dest=$2
    _hsr_parent=$(dirname "$_hsr_dest")
    _hsr_tmp="$_hsr_parent/.homeworld-link-$$-$(basename "$_hsr_dest")"
    mkdir -p "$_hsr_parent" || return 1
    rm -f "$_hsr_tmp"
    ln -s "$_hsr_target" "$_hsr_tmp" || return 1
    # POSIX mv may follow a destination symlink to a directory. GNU/BusyBox
    # provide -T and BSD/macOS provides -h; use either to replace the link name.
    if mv -fT "$_hsr_tmp" "$_hsr_dest" 2>/dev/null; then
        return 0
    fi
    if mv -fh "$_hsr_tmp" "$_hsr_dest" 2>/dev/null; then
        return 0
    fi
    # Last-resort portable fallback. It has a very small visibility gap, but
    # never follows the destination and never moves the temporary link inside it.
    rm -f "$_hsr_dest" || { rm -f "$_hsr_tmp"; return 1; }
    mv -f "$_hsr_tmp" "$_hsr_dest" || { rm -f "$_hsr_tmp"; return 1; }
}

hw_readlink_or_empty() {
    [ -L "$1" ] && readlink "$1" || printf ''
}

# Test-only interruption hook. Production behavior is unchanged unless the
# variable is deliberately set by the test suite.
hw_test_interrupt() {
    _hti_point=$1
    if [ "${HW_TEST_PAUSE_AT:-}" = "$_hti_point" ]; then
        [ -z "${HW_TEST_PAUSE_FILE:-}" ] || : > "$HW_TEST_PAUSE_FILE"
        while :; do sleep 1; done
    fi
    [ "${HW_TEST_INTERRUPT_AT:-}" = "$_hti_point" ] || return 0
    exit 143
}
