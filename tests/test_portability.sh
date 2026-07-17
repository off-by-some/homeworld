#!/bin/sh

section "all shell files parse as POSIX sh"
root=$(cd "$_TESTS_DIR/.." && pwd)
for shell_file in "$root/bin/homeworld" "$root/install.sh" "$root/lib/homeworld"/*.sh "$root/tests"/*.sh; do
    sh -n "$shell_file" || fail "sh parses $(basename "$shell_file")"
done
ok "all shell files parse with sh"

section "hostile but supported paths"
setup_env
module="$_T_TMP/module with spaces"; mkdir -p "$module/config"; printf value > "$module/config/file"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
# Generate the UTF-8 bytes for ü as bytes, not as awk characters.
# POSIX printf defines \ddd in the format string as a byte; LC_ALL=C
# avoids multibyte-locale implementations re-encoding octal escapes.
unicode_suffix=$(LC_ALL=C printf '\303\274')
gen=$(hw_gen_new); dest="$_T_TMP/path with spaces [*] $unicode_suffix"
hw_config_add config/file file "$gen" mod; hw_config_link file "$dest" mod "$gen"; hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
assert_link "$dest" "$(hw_current)/config/mod/file" "hostile destination link is created exactly"
assert_eq "$(cat "$dest")" value "spaces, glob characters, and Unicode work"
(hw_managed_link_record "$_T_TMP/bad
path" config mod/file mod "$gen") >/dev/null 2>&1
assert_nonzero "$?" "line breaks rejected explicitly"
teardown_env

section "test runner uses this checkout's binary"
expected_homeworld=$(cd "$_TESTS_DIR/../bin" && pwd)/homeworld
actual_homeworld=$(command -v homeworld)
actual_homeworld=$(cd "$(dirname "$actual_homeworld")" && pwd)/$(basename "$actual_homeworld")
assert_eq "$actual_homeworld" "$expected_homeworld" "checkout binary takes precedence over installed versions"
