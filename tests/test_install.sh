#!/bin/sh
# test_install.sh — end-to-end CLI integration tests
#
# These call the homeworld binary as a subprocess with isolated XDG directories.
# Run the bootstrap installer before running this file.

# Verify homeworld is installed before starting
if ! command -v homeworld >/dev/null 2>&1; then
    printf 'SKIP: homeworld binary not found — run install.sh first\n' >&2
    return 0
fi

# Build a reusable multi-module test source tree:
#   root       — top-level module with a command
#   worker     — sub-module with a config link; depends on root
_make_source() {
    _ms_base="$1"
    rm -rf "$_ms_base"

    make_module "$_ms_base" "root"
    make_command "$_ms_base" "rootcmd"

    make_module "$_ms_base/sub/worker" "worker" \
        'HOMEWORLD_DEPENDS="root"'
    make_config "$_ms_base/sub/worker" "workerrc" "# worker config"

    # Single-quoted heredoc: $HOME expands at runtime in the install.sh subprocess
    cat > "$_ms_base/sub/worker/install.sh" << 'INSTALLSCRIPT'
homeworld config link workerrc "$HOME/.config/workerrc"
INSTALLSCRIPT
}

section "homeworld init — local source"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"

hw_cli init "$_fix" 2>/dev/null
assert_0 $? "init exits 0"

_hd=$(hw_data_dir)
[ -L "$_hd/current" ]; assert_0 $? "current symlink created"
assert_file "$_T_XDG/xdg/state/homeworld/source" "source path recorded"
assert_file "$_T_XDG/home/.config/homeworld/env.sh" "env.sh written"

teardown_cli_env

section "homeworld init — rejects missing source"

setup_cli_env
hw_cli init "$_T_TMP/nonexistent" 2>/dev/null
assert_nonzero $? "exits non-zero for missing path"
teardown_cli_env

section "homeworld init — rejects directory without sentinel"

setup_cli_env
mkdir -p "$_T_TMP/no-sentinel"
hw_cli init "$_T_TMP/no-sentinel" 2>/dev/null
assert_nonzero $? "exits non-zero when source has no .homeworld-module"
teardown_cli_env

section "homeworld install --dry-run — no generation created"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_hd=$(hw_data_dir)
_gen_before=$(readlink "$_hd/current" 2>/dev/null)
hw_cli install --dry-run 2>/dev/null
assert_0 $? "dry-run exits 0"
_gen_after=$(readlink "$_hd/current" 2>/dev/null)
assert_eq "$_gen_before" "$_gen_after" "dry-run does not create a new generation"

teardown_cli_env

section "homeworld install — command launcher deployed"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_hd=$(hw_data_dir)
_cur=$(readlink "$_hd/current")
assert_file "$_cur/bin/rootcmd" "launcher installed in generation bin/"
[ -x "$_cur/bin/rootcmd" ]; assert_0 $? "launcher is executable"

teardown_cli_env

section "homeworld install — launcher sets HOMEWORLD_COMMAND_DIR"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_hd=$(hw_data_dir)
_cur=$(readlink "$_hd/current")
# The launcher sets HOMEWORLD_COMMAND_DIR before exec-ing run.
# Checking the launcher script content is more reliable than running it.
assert_contains "$_cur/bin/rootcmd" "HOMEWORLD_COMMAND_DIR" "launcher exports HOMEWORLD_COMMAND_DIR"
assert_contains "$_cur/bin/rootcmd" "exec" "launcher uses exec for the run file"

teardown_cli_env

section "homeworld install — config link activated"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_hd=$(hw_data_dir)
_dest="$_T_XDG/home/.config/workerrc"
[ -L "$_dest" ]; assert_0 $? "workerrc symlink created"
_target=$(readlink "$_dest" 2>/dev/null)
case "$_target" in
    "$_hd"*) ok "workerrc link points into homeworld data" ;;
    *)       fail "workerrc link target outside homeworld data: $_target" ;;
esac

teardown_cli_env

section "homeworld install — module dependency order respected"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_hd=$(hw_data_dir)
_cur=$(readlink "$_hd/current")
_meta="$_cur/.homeworld/installed-modules"
# root must appear before worker in the modules list
_pos_root=$(grep -n "root" "$_meta" 2>/dev/null | head -1 | cut -d: -f1)
_pos_worker=$(grep -n "worker" "$_meta" 2>/dev/null | head -1 | cut -d: -f1)
[ "${_pos_root:-9}" -lt "${_pos_worker:-0}" ]
assert_0 $? "root listed before worker in installed-modules"

teardown_cli_env

section "homeworld status — shows active generation"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_output=$(hw_cli status 2>&1)
assert_0 $? "status exits 0"
printf '%s' "$_output" | grep -qi "generation"; assert_0 $? "status shows generation ID"
printf '%s' "$_output" | grep -qi "platform";   assert_0 $? "status shows platform"

teardown_cli_env

section "homeworld rollback — swaps current and previous"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_hd=$(hw_data_dir)
_gen1=$(readlink "$_hd/current")
hw_cli install 2>/dev/null
_gen2=$(readlink "$_hd/current")

hw_cli rollback 2>/dev/null
assert_0 $? "rollback exits 0"
assert_link "$_hd/current" "$_gen1" "current reverts to gen1 after rollback"

teardown_cli_env

section "homeworld rollback — config links follow the rollback"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_hd=$(hw_data_dir)
_gen1=$(readlink "$_hd/current")
_dest="$_T_XDG/home/.config/workerrc"

hw_cli install 2>/dev/null
_gen2=$(readlink "$_hd/current")

hw_cli rollback 2>/dev/null
_target=$(readlink "$_dest" 2>/dev/null)
# After rollback, the link should point into gen1's config, not gen2's
case "$_target" in
    "$_gen1"*) ok "workerrc link points into gen1 after rollback" ;;
    *)         fail "workerrc link still points into gen2 or elsewhere: $_target" ;;
esac

teardown_cli_env

section "homeworld gc — removes unreferenced generation"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null

_hd=$(hw_data_dir)
_gen1=$(readlink "$_hd/current")
hw_cli install 2>/dev/null
_gen2=$(readlink "$_hd/current")
hw_cli install 2>/dev/null
_gen3=$(readlink "$_hd/current")

hw_cli gc 2>/dev/null
assert_0 $? "gc exits 0"
assert_dir    "$_gen3" "gc keeps current"
assert_dir    "$_gen2" "gc keeps previous"
assert_no_path "$_gen1" "gc removes gen1 (unreferenced)"

teardown_cli_env

section "homeworld doctor — passes after successful init"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null
hw_cli doctor 2>/dev/null
assert_0 $? "doctor exits 0 after init"
teardown_cli_env

section "homeworld doctor — warns before init"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli doctor 2>/dev/null
assert_nonzero $? "doctor exits non-zero before init"
teardown_cli_env

section "homeworld list — shows module status"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null
_output=$(hw_cli list 2>&1)
assert_0 $? "list exits 0"
printf '%s' "$_output" | grep -q "root";   assert_0 $? "root module shown"
printf '%s' "$_output" | grep -q "worker"; assert_0 $? "worker module shown"
teardown_cli_env

section "homeworld install — unknown module exits non-zero"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null
hw_cli install no-such-module 2>/dev/null
assert_nonzero $? "exits non-zero for unknown module name"
teardown_cli_env

section "hostile path names — source directory with spaces"

setup_cli_env
_fix="$_T_TMP/source with spaces"; _make_source "$_fix"
hw_cli init "$_fix" 2>/dev/null
assert_0 $? "init succeeds with spaces in source path"

_hd=$(hw_data_dir)
[ -L "$_hd/current" ]; assert_0 $? "generation created with spaced source path"
teardown_cli_env

section "hostile path names — config dest with spaces"

setup_cli_env
_fix="$_T_TMP/source"; _make_source "$_fix"

# Replace the worker install.sh to use a dest path with spaces
cat > "$_fix/sub/worker/install.sh" << 'INSTALLSCRIPT'
homeworld config link workerrc "$HOME/.config/my config file"
INSTALLSCRIPT

hw_cli init "$_fix" 2>/dev/null
assert_0 $? "init succeeds with spaces in config dest"

_dest="$_T_XDG/home/.config/my config file"
[ -L "$_dest" ]; assert_0 $? "symlink created at path with spaces"
teardown_cli_env
