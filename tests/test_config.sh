#!/bin/sh

section "config paths are module-root-relative and normalized"
setup_env
module="$_T_TMP/module"; mkdir -p "$module/config" "$module/generated"; printf one > "$module/config/workerrc"; printf two > "$module/generated/app.conf"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new)
id=$(hw_config_add config/workerrc "$gen" mod)
assert_eq "$id" workerrc "leading config prefix stripped"
assert_eq "$(cat "$gen/config/mod/workerrc")" one "config staged"
id2=$(hw_config_add generated/app.conf "$gen" mod)
assert_eq "$id2" generated/app.conf "other relative path preserved"
assert_eq "$(cat "$gen/config/mod/generated/app.conf")" two "generated config staged"
(hw_config_add /absolute "$gen" mod) >/dev/null 2>&1
assert_nonzero "$?" "absolute config source rejected"
teardown_env

section "config link ownership"
setup_env
module="$_T_TMP/module"; mkdir -p "$module/config"; printf one > "$module/config/file"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new); hw_config_link config/file "$_T_TMP/external" mod "$gen"; hw_gen_write_meta "$gen" linux test '' mod
printf unmanaged > "$_T_TMP/external"
(hw_gen_activate "$gen") >/dev/null 2>&1
assert_nonzero "$?" "unmanaged destination rejected"
assert_eq "$(cat "$_T_TMP/external")" unmanaged "unmanaged file untouched"
teardown_env
