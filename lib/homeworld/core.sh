#!/bin/sh
# core.sh — fundamental constants and utilities
# No side effects on load. Every other library depends on this one.

HW_VERSION="1.0.0"

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
