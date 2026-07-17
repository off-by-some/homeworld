#!/bin/sh
# test_cli_output.sh — human-facing CLI formatting and plan output

section "help output is grouped and grepable"

setup_cli_env
hw_cli --help >"$_T_TMP/help" 2>&1
assert_contains "$_T_TMP/help" "Usage:" "help has usage heading"
assert_contains "$_T_TMP/help" "Common commands:" "help has common command group"
assert_contains "$_T_TMP/help" "Resource lifecycle:" "help explains add/link/path verbs"
assert_contains "$_T_TMP/help" "homeworld config add <source> <name>" "help documents config add"
assert_contains "$_T_TMP/help" "homeworld asset link <name> <destination>" "help documents canonical asset link"
teardown_cli_env

section "errors use stable ERROR and HINT labels"

setup_cli_env
hw_cli no-such-command >"$_T_TMP/error" 2>&1
assert_nonzero "$?" "unknown command fails"
assert_contains "$_T_TMP/error" "homeworld: ERROR" "error label is uppercase and grepable"
assert_contains "$_T_TMP/error" "homeworld: HINT" "hint label is uppercase and grepable"
teardown_cli_env

section "module plans show nested modules"

setup_cli_env
source_dir="$_T_TMP/source"
make_module "$source_dir" root
make_module "$source_dir/tools/docker" docker 'HOMEWORLD_DESCRIPTION="Docker utilities"'
make_module "$source_dir/tools/docker/linux" docker-linux 'HOMEWORLD_DESCRIPTION="Docker on Linux"'
make_module "$source_dir/tools/docker/macos" docker-macos 'HOMEWORLD_DESCRIPTION="Docker alternate platform"
HOMEWORLD_DISTROS="homeworld-test-distro-that-should-never-match"'
make_module "$source_dir/tools/node" node 'HOMEWORLD_DESCRIPTION="Node runtime"'

hw_cli install --dry-run --source "$source_dir" >"$_T_TMP/plan" 2>&1
assert_0 "$?" "dry-run install succeeds"
assert_contains "$_T_TMP/plan" "Module plan:" "plan heading is present"
assert_contains "$_T_TMP/plan" "STATUS" "plan has status header"
assert_contains "$_T_TMP/plan" "INSTALL  docker" "top-level module appears without nesting indent"
assert_contains "$_T_TMP/plan" "INSTALL    docker-linux" "nested module appears indented in module column"
assert_contains "$_T_TMP/plan" "SKIP" "plan includes skipped status"
assert_contains "$_T_TMP/plan" "docker-macos" "skipped nested module name is shown"
assert_contains "$_T_TMP/plan" "distro" "skip reason is shown"
teardown_cli_env

section "list writes the module table to stdout"

setup_cli_env
source_dir="$_T_TMP/list-source"
make_module "$source_dir" root
make_module "$source_dir/tools/docker" docker 'HOMEWORLD_DESCRIPTION="Docker utilities"'
make_module "$source_dir/tools/docker/linux" docker-linux 'HOMEWORLD_DESCRIPTION="Docker on Linux"'
hw_cli init "$source_dir" >"$_T_TMP/init.out" 2>"$_T_TMP/init.err"
assert_0 "$?" "init succeeds"
hw_cli list >"$_T_TMP/list.out" 2>"$_T_TMP/list.err"
assert_0 "$?" "list succeeds"
assert_contains "$_T_TMP/list.out" "STATUS" "list table is on stdout"
assert_contains "$_T_TMP/list.out" "INSTALL    docker-linux" "list preserves nested indentation"
teardown_cli_env
