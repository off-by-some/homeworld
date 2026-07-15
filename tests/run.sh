#!/bin/sh
# Run one test file in-process, or every test file in an isolated shell.
set -u

_TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
_LIB_DIR=$(cd "$_TESTS_DIR/../lib/homeworld" && pwd)

if [ $# -eq 0 ]; then
    _runner=${HOMEWORLD_TEST_SHELL:-sh}
    _failed=0
    _run_tmp=$(mktemp -d)
    _jobs="$_run_tmp/jobs"
    : > "$_jobs"
    _index=0
    _batch=0

    _wait_batch() {
        while IFS='|' read -r _pid _log; do
            [ -n "$_pid" ] || continue
            wait "$_pid" || _failed=1
            cat "$_log"
        done < "$_jobs"
        : > "$_jobs"
        _batch=0
    }

    for _file in "$_TESTS_DIR"/test_*.sh; do
        [ -f "$_file" ] || continue
        _index=$((_index + 1))
        _batch=$((_batch + 1))
        _log="$_run_tmp/$_index.log"
        # Test files use isolated temporary roots, so small parallel batches are safe.
        # Intentional word splitting allows HOMEWORLD_TEST_SHELL="busybox ash".
        # shellcheck disable=SC2086
        $_runner "$0" "$(basename "$_file")" > "$_log" 2>&1 &
        printf '%s|%s
' "$!" "$_log" >> "$_jobs"
        [ "$_batch" -lt 3 ] || _wait_batch
    done
    [ "$_batch" -eq 0 ] || _wait_batch
    rm -rf "$_run_tmp"
    exit "$_failed"
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
