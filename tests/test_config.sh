#!/bin/sh

section "config add snapshots named resources"
setup_env
module="$_T_TMP/module"; mkdir -p "$module/config" "$module/generated"; printf one > "$module/config/workerrc"; printf two > "$module/generated/app.conf"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new)
hw_config_add config/workerrc workerrc "$gen" mod
assert_eq "$(cat "$gen/config/mod/workerrc")" one "config staged by explicit name"
hw_config_add generated/app.conf app-conf "$gen" mod
assert_eq "$(cat "$gen/config/mod/app-conf")" two "generated config staged by explicit name"
(hw_config_add /absolute absolute "$gen" mod) >/dev/null 2>&1
assert_nonzero "$?" "absolute config source rejected"
(hw_config_add config/workerrc 'bad/name' "$gen" mod) >/dev/null 2>&1
assert_nonzero "$?" "invalid config name rejected"
teardown_env

section "config link uses existing named resources"
setup_env
module="$_T_TMP/module"; mkdir -p "$module/config"; printf one > "$module/config/file"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new)
hw_config_add config/file file "$gen" mod
hw_config_link file "$_T_TMP/external" mod "$gen"
hw_gen_write_meta "$gen" linux test '' mod
hw_gen_activate "$gen"
assert_link "$_T_TMP/external" "$(hw_current)/config/mod/file" "config link follows current"
assert_eq "$(cat "$_T_TMP/external")" one "linked named config is readable"
teardown_env

section "config link ownership"
setup_env
module="$_T_TMP/module"; mkdir -p "$module/config"; printf one > "$module/config/file"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new); hw_config_add config/file file "$gen" mod; hw_config_link file "$_T_TMP/external" mod "$gen"; hw_gen_write_meta "$gen" linux test '' mod
printf unmanaged > "$_T_TMP/external"
(hw_gen_activate "$gen") >/dev/null 2>&1
assert_nonzero "$?" "unmanaged destination rejected"
assert_eq "$(cat "$_T_TMP/external")" unmanaged "unmanaged file untouched"
teardown_env

section "config overlays compose immutable repository views"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" original
module="$_T_TMP/module"; mkdir -p "$module/config"; printf patched > "$module/config/file"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new)
hw_repo_add_to_gen "$repo" tools "$gen" ''
repo_path=$(HOMEWORLD_TARGET="$gen" hw_repo_path tools)
hw_config_add config/file replacement "$gen" mod
hw_config_link replacement "$repo_path/file.txt" mod "$gen"
view=$(HOMEWORLD_TARGET="$gen" hw_repo_path tools)
assert_eq "$(cat "$view/file.txt")" patched "config replaces repository file in pending view"
checkout=$(cd "$gen/repos/tools" && pwd -P)
assert_eq "$(cat "$checkout/file.txt")" original "immutable checkout remains unmodified"
teardown_env

section "config CLI rejects old combined link form"
setup_cli_env
source_dir="$_T_TMP/source"; make_module "$source_dir" root
mkdir -p "$source_dir/config"; printf value > "$source_dir/config/value"
cat > "$source_dir/install.sh" <<EOF2
#!/bin/sh
homeworld config link config/value value "$_T_TMP/home/value"
EOF2
chmod +x "$source_dir/install.sh"
hw_cli init "$source_dir" >/dev/null 2>&1
assert_nonzero "$?" "old config link form rejected"
assert_no_path "$_T_TMP/home/value" "rejected form creates no link"
teardown_cli_env
