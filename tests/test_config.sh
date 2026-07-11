#!/bin/sh
# test_config.sh — config link staging, activation, and reconciliation

section "hw_config_link — stages file and records link"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "cfg"; make_config "$_mod" "myrc" "# content"
_gen=$(hw_gen_new)
_dest="$_T_TMP/home/.config/myrc"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="cfg" \
HOMEWORLD_TARGET="$_gen" \
    hw_config_link "myrc" "$_dest" "cfg" "$_gen"

assert_file "$_gen/config/cfg/myrc" "file staged into generation"
assert_file "$_gen/.homeworld/managed-links" "managed-links created"
assert_contains "$_gen/.homeworld/managed-links" "$_dest" "destination in managed-links"
teardown_env

section "hw_config_link — destination must be absolute"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "cfg"; make_config "$_mod" "rc" "x"
_gen=$(hw_gen_new)

( HOMEWORLD_MODULE_ROOT="$_mod" \
  HOMEWORLD_MODULE_NAME="cfg" \
  HOMEWORLD_TARGET="$_gen" \
  hw_config_link "rc" "relative/path" "cfg" "$_gen" ) 2>/dev/null
assert_nonzero $? "rejects relative destination"

teardown_env

section "hw_config_link — source path safety"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "cfg"; make_config "$_mod" "rc" "x"
_gen=$(hw_gen_new)
_dest="$_T_TMP/home/.config/rc"

# Path traversal in source
( HOMEWORLD_MODULE_ROOT="$_mod" \
  HOMEWORLD_MODULE_NAME="cfg" \
  HOMEWORLD_TARGET="$_gen" \
  hw_config_link "../escape" "$_dest" "cfg" "$_gen" ) 2>/dev/null
assert_nonzero $? "rejects .. in source path"

# Absolute source path
( HOMEWORLD_MODULE_ROOT="$_mod" \
  HOMEWORLD_MODULE_NAME="cfg" \
  HOMEWORLD_TARGET="$_gen" \
  hw_config_link "/etc/passwd" "$_dest" "cfg" "$_gen" ) 2>/dev/null
assert_nonzero $? "rejects absolute source path"

# Non-existent source file
( HOMEWORLD_MODULE_ROOT="$_mod" \
  HOMEWORLD_MODULE_NAME="cfg" \
  HOMEWORLD_TARGET="$_gen" \
  hw_config_link "nonexistent" "$_dest" "cfg" "$_gen" ) 2>/dev/null
assert_nonzero $? "rejects non-existent source file"

teardown_env

section "hw_config_link — cross-module conflict"

setup_env
_ma="$_T_TMP/ma"; make_module "$_ma" "mod-a"; make_config "$_ma" "shared" "a"
_mb="$_T_TMP/mb"; make_module "$_mb" "mod-b"; make_config "$_mb" "shared" "b"
_gen=$(hw_gen_new)
_dest="$_T_TMP/home/.config/shared"

HOMEWORLD_MODULE_ROOT="$_ma" \
HOMEWORLD_MODULE_NAME="mod-a" \
HOMEWORLD_TARGET="$_gen" \
    hw_config_link "shared" "$_dest" "mod-a" "$_gen"

( HOMEWORLD_MODULE_ROOT="$_mb" \
  HOMEWORLD_MODULE_NAME="mod-b" \
  HOMEWORLD_TARGET="$_gen" \
  hw_config_link "shared" "$_dest" "mod-b" "$_gen" ) 2>/dev/null
assert_nonzero $? "rejects cross-module conflict for same destination"

teardown_env

section "hw_config_link — same module re-declaring the same link is idempotent"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "idem"; make_config "$_mod" "rc" "x"
_gen=$(hw_gen_new)
_dest="$_T_TMP/home/.config/rc"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="idem" \
HOMEWORLD_TARGET="$_gen" \
    hw_config_link "rc" "$_dest" "idem" "$_gen"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="idem" \
HOMEWORLD_TARGET="$_gen" \
    hw_config_link "rc" "$_dest" "idem" "$_gen"
assert_0 $? "second declaration by same module succeeds"

_count=$(grep -c "$_dest" "$_gen/.homeworld/managed-links" 2>/dev/null || printf 0)
assert_eq "$_count" "1" "no duplicate entry in managed-links"
teardown_env

section "hw_config_activate — creates symlink at destination"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "act"; make_config "$_mod" "rc" "content"
_gen=$(hw_gen_new)
_dest="$_T_TMP/home/.config/activatedrc"
mkdir -p "$(dirname "$_dest")"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="act" \
HOMEWORLD_TARGET="$_gen" \
    hw_config_link "rc" "$_dest" "act" "$_gen"

hw_config_activate "$_gen"
assert_link "$_dest" "$_gen/config/act/rc" "symlink created at destination"
teardown_env

section "hw_config_activate — creates missing parent directories"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "act"; make_config "$_mod" "rc" "x"
_gen=$(hw_gen_new)
_dest="$_T_TMP/home/deep/nested/dir/rc"  # parent doesn't exist yet

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="act" \
HOMEWORLD_TARGET="$_gen" \
    hw_config_link "rc" "$_dest" "act" "$_gen"

hw_config_activate "$_gen"
assert_link "$_dest" "$_gen/config/act/rc" "symlink created in deep path"
teardown_env

section "hw_config_activate — refuses to overwrite an unmanaged file"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "guard"; make_config "$_mod" "rc" "x"
_gen=$(hw_gen_new)
_dest="$_T_TMP/home/.config/guardedrc"
mkdir -p "$(dirname "$_dest")"
printf 'pre-existing content\n' > "$_dest"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="guard" \
HOMEWORLD_TARGET="$_gen" \
    hw_config_link "rc" "$_dest" "guard" "$_gen"

( hw_config_activate "$_gen" ) 2>/dev/null
assert_nonzero $? "refuses to overwrite unmanaged file"
assert_file "$_dest" "original file left intact"
teardown_env

section "hw_config_activate — refuses to overwrite a foreign symlink"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "guard"; make_config "$_mod" "rc" "x"
_gen=$(hw_gen_new)
_dest="$_T_TMP/home/.config/foreignrc"
mkdir -p "$(dirname "$_dest")"
ln -s "/tmp/user-owns-this" "$_dest"  # foreign symlink

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="guard" \
HOMEWORLD_TARGET="$_gen" \
    hw_config_link "rc" "$_dest" "guard" "$_gen"

( hw_config_activate "$_gen" ) 2>/dev/null
assert_nonzero $? "refuses to overwrite foreign symlink"
assert_link "$_dest" "/tmp/user-owns-this" "foreign symlink left intact"
teardown_env

section "hw_config_activate — updates an existing homeworld-managed symlink"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "upd"; make_config "$_mod" "rc" "v1"
_gen1=$(hw_gen_new); _gen2=$(hw_gen_new)
_dest="$_T_TMP/home/.config/updaterc"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="upd" \
HOMEWORLD_TARGET="$_gen1" \
    hw_config_link "rc" "$_dest" "upd" "$_gen1"
hw_config_activate "$_gen1"

# Also declare in gen2 (simulating an upgrade)
HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="upd" \
HOMEWORLD_TARGET="$_gen2" \
    hw_config_link "rc" "$_dest" "upd" "$_gen2"
hw_config_activate "$_gen2"

assert_link "$_dest" "$_gen2/config/upd/rc" "symlink updated to new generation"
teardown_env

section "hw_config_reconcile — removes stale links dropped by new generation"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "recon"; make_config "$_mod" "rc" "x"
_gen1=$(hw_gen_new); _gen2=$(hw_gen_new)
_dest="$_T_TMP/home/.config/reconrc"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="recon" \
HOMEWORLD_TARGET="$_gen1" \
    hw_config_link "rc" "$_dest" "recon" "$_gen1"
hw_config_activate "$_gen1"

# gen2 does not declare $dest — reconcile should remove the stale link
hw_config_activate "$_gen2"
hw_config_reconcile "$_gen1" "$_gen2"
assert_no_path "$_dest" "stale link removed after reconcile"
teardown_env

section "hw_config_reconcile — leaves externally modified links alone"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "ext"; make_config "$_mod" "rc" "x"
_gen1=$(hw_gen_new); _gen2=$(hw_gen_new)
_dest="$_T_TMP/home/.config/extrc"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="ext" \
HOMEWORLD_TARGET="$_gen1" \
    hw_config_link "rc" "$_dest" "ext" "$_gen1"
hw_config_activate "$_gen1"

# User replaces the managed symlink with their own
mkdir -p "$(dirname "$_dest")"
ln -sf "/tmp/user-custom" "$_dest"

hw_config_activate "$_gen2"
hw_config_reconcile "$_gen1" "$_gen2"
assert_link "$_dest" "/tmp/user-custom" "user-modified link left alone by reconcile"
teardown_env

section "hw_config_reconcile — keeps links still present in new generation"

setup_env
_mod="$_T_TMP/mod"; make_module "$_mod" "keep"; make_config "$_mod" "rc" "x"
_gen1=$(hw_gen_new); _gen2=$(hw_gen_new)
_dest="$_T_TMP/home/.config/keeprc"

# Both gens declare the same link
HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="keep" \
HOMEWORLD_TARGET="$_gen1" \
    hw_config_link "rc" "$_dest" "keep" "$_gen1"
hw_config_activate "$_gen1"

HOMEWORLD_MODULE_ROOT="$_mod" \
HOMEWORLD_MODULE_NAME="keep" \
HOMEWORLD_TARGET="$_gen2" \
    hw_config_link "rc" "$_dest" "keep" "$_gen2"
hw_config_activate "$_gen2"
hw_config_reconcile "$_gen1" "$_gen2"

# The link should now point to gen2's staged copy (updated by gen2 activation)
assert_link "$_dest" "$_gen2/config/keep/rc" "link updated to gen2, not removed"
teardown_env
