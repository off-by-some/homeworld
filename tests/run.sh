#!/bin/sh
# run.sh — homeworld test runner
#
# Usage:
#   sh tests/run.sh                 — run all test files
#   sh tests/run.sh test_core.sh   — run one specific file
#
# The homeworld lib is written for Bash 3.2+. Re-exec with bash if we were
# invoked by a POSIX sh (e.g. /bin/sh on macOS) so the library parses cleanly.
if [ -z "${BASH_VERSION:-}" ]; then
    command -v bash >/dev/null 2>&1 || {
        printf 'homeworld tests require Bash 3.2 or newer\n' >&2
        exit 1
    }
    exec bash "$0" "$@"
fi

set -u

_TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
_LIB_DIR=$(cd "$_TESTS_DIR/../lib/homeworld" && pwd)

# If homeworld is not already on PATH, add the source-tree bin/ so that
# test_install.sh can run integration tests without a prior global install.
if ! command -v homeworld >/dev/null 2>&1; then
    PATH="$_TESTS_DIR/../bin:$PATH"
    export PATH
fi

# Source the library. core.sh runs the color-init block at load time, which
# makes the _HW_C_* variables available to the framework and test files.
. "$_LIB_DIR/core.sh"
. "$_LIB_DIR/platform.sh"
. "$_LIB_DIR/module.sh"
. "$_LIB_DIR/generation.sh"
. "$_LIB_DIR/install.sh"
. "$_LIB_DIR/config.sh"

. "$_TESTS_DIR/framework.sh"

if [ $# -gt 0 ]; then
    # Run a single named file
    _target="$_TESTS_DIR/$1"
    [ -f "$_target" ] || {
        printf 'run.sh: no such test file: %s\n' "$1" >&2
        exit 2
    }
    printf '%s=== %s ===%s\n' "$_HW_C_BOLD" "$(basename "$1" .sh)" "$_HW_C_RST" >&2
    . "$_target"
else
    # Run everything
    for _f in "$_TESTS_DIR"/test_*.sh; do
        [ -f "$_f" ] || continue
        printf '\n%s=== %s ===%s\n' \
            "$_HW_C_BOLD" "$(basename "$_f" .sh)" "$_HW_C_RST" >&2
        . "$_f"
    done
fi

t_summary
