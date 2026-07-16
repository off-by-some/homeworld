#!/bin/sh
# Run one test file in-process, or every test file in an isolated shell.
set -u

_TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
_LIB_DIR=$(cd "$_TESTS_DIR/../lib/homeworld" && pwd)

if [ $# -eq 0 ]; then
    _runner=${HOMEWORLD_TEST_SHELL:-sh}

    # Run test files one at a time. Several suites exercise process signals,
    # locks, and temporary filesystem state, so concurrent execution is not
    # deterministic across shells and operating systems.
    for _file in "$_TESTS_DIR"/test_*.sh; do
        [ -f "$_file" ] || continue
        _test_name=$(basename "$_file")

        # Intentional word splitting allows HOMEWORLD_TEST_SHELL="busybox ash".
        # shellcheck disable=SC2086
        $_runner "$0" "$_test_name"
        _status=$?

        if [ "$_status" -ne 0 ]; then
            printf '\nrun.sh: %s failed under %s with status %s\n' \
                "$_test_name" "$_runner" "$_status" >&2
            exit "$_status"
        fi
    done

    printf '\nrun.sh: all test files passed under %s\n' "$_runner" >&2
    exit 0
fi

# Always test the binary from this checkout. A developer may already have an
# older Homeworld on PATH, and allowing that binary to win makes the suite test
# a mixture of old CLI code and new library code.
PATH="$_TESTS_DIR/../bin:$PATH"
export PATH

# Keep tests independent from the machine's Git configuration and credential
# helpers. Individual fixtures provide the identity needed for commits.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_TERMINAL_PROMPT

. "$_LIB_DIR/core.sh"
. "$_LIB_DIR/platform.sh"
. "$_LIB_DIR/module.sh"
. "$_LIB_DIR/transaction.sh"
. "$_LIB_DIR/state.sh"
. "$_LIB_DIR/repo.sh"
. "$_LIB_DIR/config.sh"
. "$_LIB_DIR/generation.sh"
. "$_LIB_DIR/install.sh"
. "$_TESTS_DIR/framework.sh"

_target="$_TESTS_DIR/$1"
[ -f "$_target" ] || { printf 'run.sh: no such test file: %s\n' "$1" >&2; exit 2; }
printf '\n%s=== %s ===%s\n' "$_HW_C_BOLD" "$(basename "$1" .sh)" "$_HW_C_RST" >&2
. "$_target"
t_summary
