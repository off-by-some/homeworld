#!/bin/sh
set -eu

# Bootstrap installer — drop homeworld into ~/.local/bin and ~/.local/lib.
# Safe to rerun: it overwrites the previous installation cleanly.

# Resolve the directory containing this script. cd -P follows symlinks so
# running `sh <(curl ...)` or a symlinked copy works correctly.
_hw_script_dir=$(cd -P "$(dirname "$0")" 2>/dev/null && pwd) || {
    printf 'homeworld installer: cannot determine script directory\n' >&2
    exit 1
}

_hw_bin_src="$_hw_script_dir/bin/homeworld"
_hw_lib_src="$_hw_script_dir/lib/homeworld"

if [ ! -f "$_hw_bin_src" ]; then
    printf 'homeworld installer: bin/homeworld not found at %s\n' "$_hw_bin_src" >&2
    exit 1
fi
if [ ! -d "$_hw_lib_src" ]; then
    printf 'homeworld installer: lib/homeworld not found at %s\n' "$_hw_lib_src" >&2
    exit 1
fi

_hw_tests="$_hw_script_dir/tests/run.sh"
_hw_dest_bin="${HOME}/.local/bin"
_hw_dest_lib="${HOME}/.local/lib"

# Run the unit test suite before touching anything on the system.
# Integration tests (test_install.sh) self-skip when homeworld is not yet on
# PATH, so this is safe on both first install and upgrades.
if [ -f "$_hw_tests" ]; then
    printf 'Running tests...\n\n'
    if ! sh "$_hw_tests"; then
        printf '\nhomeworld installer: tests failed — installation aborted\n' >&2
        printf 'Fix the failures above, then run this installer again.\n' >&2
        exit 1
    fi
    printf '\n'
fi

mkdir -p "$_hw_dest_bin" "$_hw_dest_lib"

# Install the main binary
cp "$_hw_bin_src" "$_hw_dest_bin/homeworld"
chmod +x "$_hw_dest_bin/homeworld"

# Install the library — remove the old tree first so stale files don't linger
rm -rf "$_hw_dest_lib/homeworld"
cp -r "$_hw_lib_src" "$_hw_dest_lib/homeworld"

printf 'Homeworld installed to %s/homeworld\n' "$_hw_dest_bin"
printf "Run 'homeworld init <source>' to get started.\n"

# Offer to run the full suite now that the binary is on PATH
if [ -f "$_hw_tests" ]; then
    printf '\nRun the full test suite (including integration tests):\n'
    printf '  sh %s\n' "$_hw_tests"
fi

# Friendly reminder if the install destination is not on PATH yet
case ":${PATH}:" in
    *":${_hw_dest_bin}:"*) ;;
    *)
        printf '\nNote: %s is not on your PATH.\n' "$_hw_dest_bin"
        printf 'Add this line to your shell profile:\n'
        printf '  export PATH="%s:$PATH"\n' "$_hw_dest_bin"
        ;;
esac
