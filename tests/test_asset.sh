#!/bin/sh

section "asset add and link"
setup_env
module="$_T_TMP/module"; mkdir -p "$module"; printf theme > "$module/theme"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new)
hw_asset_add theme theme "$gen" mod
assert_eq "$(cat "$gen/assets/mod/theme")" theme "asset staged"
hw_asset_link theme linked "$_T_TMP/external" "$gen" mod
hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
assert_link "$_T_TMP/external" "$(hw_current)/assets/mod/linked" "asset link follows current"
ln -s "$module/theme" "$module/symlink"
(hw_asset_add symlink bad "$gen" mod) >/dev/null 2>&1
assert_nonzero "$?" "symlink asset source rejected"
teardown_env
