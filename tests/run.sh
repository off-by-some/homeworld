#!/bin/sh
# run.sh — homeworld test runner
#
# Usage:
#   sh tests/run.sh                 — run all test files
#   sh tests/run.sh test_core.sh   — run one specific file
#
# The runner sources the homeworld library directly so unit test files can call
# library functions without going through the CLI binary. Integration tests
# (test_install.sh) invoke the binary as a subprocess and require it to be
# installed on PATH first (run homeworld/install.sh).

set -u

_TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
_LIB_DIR=$(cd "$_TESTS_DIR/../lib/homeworld" && pwd)

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
