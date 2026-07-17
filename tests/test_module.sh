#!/bin/sh
# test_module.sh — manifest loading, discovery, topological sort, command collision

section "hw_module_load — valid manifest"

setup_env
_src="$_T_TMP/src"
make_module "$_src" "mymod"
_name=$(hw_module_load "$_src/.homeworld-module" "$_T_TMP/mdir")
assert_eq "$_name" "mymod"         "returns module name"
assert_file "$_T_TMP/mdir/mymod/path"        "writes path field"
assert_file "$_T_TMP/mdir/mymod/description" "writes description field"
assert_eq "$(cat "$_T_TMP/mdir/mymod/description")" "test module mymod" "description value correct"
assert_eq "$(cat "$_T_TMP/mdir/mymod/auto_install")" "true" "auto_install defaults to true"
teardown_env

section "hw_module_load — all optional fields"

setup_env
_src="$_T_TMP/src"
make_module "$_src" "full" \
    'HOMEWORLD_PLATFORMS="linux macos"
HOMEWORLD_DISTROS="manjaro ubuntu"
HOMEWORLD_DEPENDS="base utils"
HOMEWORLD_AUTO_INSTALL="false"
HOMEWORLD_REQUIRES="1.2.0"'
hw_module_load "$_src/.homeworld-module" "$_T_TMP/mdir" >/dev/null
assert_eq "$(cat "$_T_TMP/mdir/full/platforms")"    "linux macos"   "platforms field"
assert_eq "$(cat "$_T_TMP/mdir/full/distros")"      "manjaro ubuntu" "distros field"
assert_eq "$(cat "$_T_TMP/mdir/full/depends")"      "base utils"    "depends field"
assert_eq "$(cat "$_T_TMP/mdir/full/auto_install")" "false"         "auto_install field"
assert_eq "$(cat "$_T_TMP/mdir/full/requires")"     "1.2.0"        "requires field"
teardown_env

section "hw_module_load — malformed manifests"

setup_env
_mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"

# Missing name entirely
mkdir -p "$_T_TMP/noname"
printf 'HOMEWORLD_DESCRIPTION="no name"\n' > "$_T_TMP/noname/.homeworld-module"
( hw_module_load "$_T_TMP/noname/.homeworld-module" "$_mdir" ) 2>/dev/null
assert_nonzero $? "rejects missing HOMEWORLD_MODULE_NAME"

# Unrecognised HOMEWORLD_* field (catches typos)
make_module "$_T_TMP/typo" "typo"
printf 'HOMEWORLD_TYPO="oops"\n' >> "$_T_TMP/typo/.homeworld-module"
( hw_module_load "$_T_TMP/typo/.homeworld-module" "$_mdir" ) 2>/dev/null
assert_nonzero $? "rejects unknown HOMEWORLD_* field"

# Uppercase letters in name
mkdir -p "$_T_TMP/upper"
printf 'HOMEWORLD_MODULE_NAME="MyMod"\n' > "$_T_TMP/upper/.homeworld-module"
( hw_module_load "$_T_TMP/upper/.homeworld-module" "$_mdir" ) 2>/dev/null
assert_nonzero $? "rejects uppercase in module name"

# Name starting with a hyphen
mkdir -p "$_T_TMP/hyphen"
printf 'HOMEWORLD_MODULE_NAME="-bad"\n' > "$_T_TMP/hyphen/.homeworld-module"
( hw_module_load "$_T_TMP/hyphen/.homeworld-module" "$_mdir" ) 2>/dev/null
assert_nonzero $? "rejects name starting with hyphen"

# Name with a space
mkdir -p "$_T_TMP/spaces"
printf 'HOMEWORLD_MODULE_NAME="with space"\n' > "$_T_TMP/spaces/.homeworld-module"
( hw_module_load "$_T_TMP/spaces/.homeworld-module" "$_mdir" ) 2>/dev/null
assert_nonzero $? "rejects name with spaces"

# Name starting with a dot
mkdir -p "$_T_TMP/dotstart"
printf 'HOMEWORLD_MODULE_NAME=".hidden"\n' > "$_T_TMP/dotstart/.homeworld-module"
( hw_module_load "$_T_TMP/dotstart/.homeworld-module" "$_mdir" ) 2>/dev/null
assert_nonzero $? "rejects name starting with dot"

teardown_env

section "hw_module_load — valid edge-case names"

setup_env
_mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"

mkdir -p "$_T_TMP/dashes"
printf 'HOMEWORLD_MODULE_NAME="my-module-name"\n' > "$_T_TMP/dashes/.homeworld-module"
hw_module_load "$_T_TMP/dashes/.homeworld-module" "$_mdir" >/dev/null
assert_0 $? "accepts hyphens in name"

mkdir -p "$_T_TMP/dots"
printf 'HOMEWORLD_MODULE_NAME="v1.2"\n' > "$_T_TMP/dots/.homeworld-module"
hw_module_load "$_T_TMP/dots/.homeworld-module" "$_mdir" >/dev/null
assert_0 $? "accepts dots in name"

mkdir -p "$_T_TMP/nums"
printf 'HOMEWORLD_MODULE_NAME="2fa-helper"\n' > "$_T_TMP/nums/.homeworld-module"
hw_module_load "$_T_TMP/nums/.homeworld-module" "$_mdir" >/dev/null
assert_0 $? "accepts name starting with digit"

teardown_env

section "hw_module_discover — finds modules recursively"

setup_env
_src="$_T_TMP/src"; _mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"
make_module "$_src" "root"
make_module "$_src/sub/alpha" "alpha"
make_module "$_src/sub/beta" "beta"
make_module "$_src/sub/alpha/nested" "nested"

_names=$(hw_module_discover "$_src" "$_mdir")
printf '%s' "$_names" | grep -q "root";   assert_0 $? "discovers root module"
printf '%s' "$_names" | grep -q "alpha";  assert_0 $? "discovers nested alpha"
printf '%s' "$_names" | grep -q "beta";   assert_0 $? "discovers nested beta"
printf '%s' "$_names" | grep -q "nested"; assert_0 $? "discovers doubly-nested module"
teardown_env

section "hw_module_discover — missing root sentinel"

setup_env
_nosrc="$_T_TMP/nosrc"; mkdir -p "$_nosrc"
_mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"
( hw_module_discover "$_nosrc" "$_mdir" ) 2>/dev/null
assert_nonzero $? "dies when source root has no .homeworld-module"
teardown_env

section "hw_module_discover — propagates error from malformed nested manifest"

setup_env
_src="$_T_TMP/src"; _mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"
make_module "$_src" "root"
mkdir -p "$_src/broken"
printf 'HOMEWORLD_MODULE_NAME="Bad Name"\n' > "$_src/broken/.homeworld-module"
( hw_module_discover "$_src" "$_mdir" ) 2>/dev/null
assert_nonzero $? "propagates error from malformed nested manifest"
teardown_env

section "hw_module_sort — topological ordering"

setup_env
_mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"

# Single module: returned as-is
make_module "$_T_TMP/ma" "alpha"
hw_module_load "$_T_TMP/ma/.homeworld-module" "$_mdir" >/dev/null
_sorted=$(hw_module_sort "$_mdir" "alpha")
assert_eq "$_sorted" "alpha" "single module with no deps"

# Linear chain: c depends on b, b depends on a → sorted: a b c
make_module "$_T_TMP/mb" "bravo"
make_module "$_T_TMP/mc" "charlie" 'HOMEWORLD_DEPENDS="bravo"'
make_module "$_T_TMP/md" "delta"   'HOMEWORLD_DEPENDS="charlie"'
hw_module_load "$_T_TMP/mb/.homeworld-module" "$_mdir" >/dev/null
hw_module_load "$_T_TMP/mc/.homeworld-module" "$_mdir" >/dev/null
hw_module_load "$_T_TMP/md/.homeworld-module" "$_mdir" >/dev/null
_sorted=$(hw_module_sort "$_mdir" "delta charlie bravo")

# Check relative ordering: bravo before charlie, charlie before delta
_pos_b=$(printf '%s' "$_sorted" | tr ' ' '\n' | grep -n "^bravo$"   | cut -d: -f1)
_pos_c=$(printf '%s' "$_sorted" | tr ' ' '\n' | grep -n "^charlie$" | cut -d: -f1)
_pos_d=$(printf '%s' "$_sorted" | tr ' ' '\n' | grep -n "^delta$"   | cut -d: -f1)
[ "${_pos_b:-9}" -lt "${_pos_c:-0}" ]; assert_0 $? "bravo before charlie"
[ "${_pos_c:-9}" -lt "${_pos_d:-0}" ]; assert_0 $? "charlie before delta"

teardown_env

section "hw_module_sort — cycle detection"

setup_env
_mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"

make_module "$_T_TMP/p1" "ping" 'HOMEWORLD_DEPENDS="pong"'
make_module "$_T_TMP/p2" "pong" 'HOMEWORLD_DEPENDS="ping"'
hw_module_load "$_T_TMP/p1/.homeworld-module" "$_mdir" >/dev/null
hw_module_load "$_T_TMP/p2/.homeworld-module" "$_mdir" >/dev/null
( hw_module_sort "$_mdir" "ping pong" ) 2>/dev/null
assert_nonzero $? "detects two-module dependency cycle"

teardown_env

section "hw_module_check_commands — collision detection"

setup_env
_mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"

# Two modules providing the same command name
make_module "$_T_TMP/ma" "mod-a"; make_command "$_T_TMP/ma" "shared-tool"
make_module "$_T_TMP/mb" "mod-b"; make_command "$_T_TMP/mb" "shared-tool"
hw_module_load "$_T_TMP/ma/.homeworld-module" "$_mdir" >/dev/null
hw_module_load "$_T_TMP/mb/.homeworld-module" "$_mdir" >/dev/null
( hw_module_check_commands "$_mdir" "mod-a mod-b" ) 2>/dev/null
assert_nonzero $? "detects duplicate command name across modules"

# Same module, multiple unique commands — fine
make_module "$_T_TMP/mc" "mod-c"
make_command "$_T_TMP/mc" "tool-one"
make_command "$_T_TMP/mc" "tool-two"
hw_module_load "$_T_TMP/mc/.homeworld-module" "$_mdir" >/dev/null
hw_module_check_commands "$_mdir" "mod-c"
assert_0 $? "multiple distinct commands in one module is fine"

teardown_env

section "hw_module_applicable — platform and distro filtering"

setup_env
_mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"

# No platform constraint: applicable everywhere
make_module "$_T_TMP/any" "any"
hw_module_load "$_T_TMP/any/.homeworld-module" "$_mdir" >/dev/null
hw_module_applicable "$_mdir" "any" "linux" "manjaro"
assert_0 $? "no constraint: applicable on linux/manjaro"
hw_module_applicable "$_mdir" "any" "macos" ""
assert_0 $? "no constraint: applicable on macos"

# Linux-only module
make_module "$_T_TMP/lnx" "lnx" 'HOMEWORLD_PLATFORMS="linux"'
hw_module_load "$_T_TMP/lnx/.homeworld-module" "$_mdir" >/dev/null
hw_module_applicable "$_mdir" "lnx" "linux" ""
assert_0 $? "linux module applicable on linux"
hw_module_applicable "$_mdir" "lnx" "macos" "" 2>/dev/null
assert_nonzero $? "linux module skipped on macos"

# Distro-restricted module
make_module "$_T_TMP/mja" "mja" 'HOMEWORLD_DISTROS="manjaro"'
hw_module_load "$_T_TMP/mja/.homeworld-module" "$_mdir" >/dev/null
hw_module_applicable "$_mdir" "mja" "linux" "manjaro"
assert_0 $? "distro module applicable on manjaro"
hw_module_applicable "$_mdir" "mja" "linux" "ubuntu" 2>/dev/null
assert_nonzero $? "distro module skipped on ubuntu"

teardown_env

section "hw_module_display_name — path nesting"

setup_env
_src="$_T_TMP/src"; _mdir="$_T_TMP/mdir"; mkdir -p "$_mdir"
make_module "$_src" "root"
make_module "$_src/tools/docker" "docker"
make_module "$_src/tools/docker/linux" "docker-linux"
make_module "$_src/tools/docker/linux/gpu" "docker-gpu"
make_module "$_src/tools/node" "node"
_names=$(hw_module_discover "$_src" "$_mdir")
assert_eq "$(hw_module_tree_depth "$_mdir" root "$_names")" "0" "root module has depth zero"
assert_eq "$(hw_module_display_name "$_mdir" docker "$_names")" "docker" "top-level child is not indented by root"
assert_eq "$(hw_module_display_name "$_mdir" docker-linux "$_names")" "  docker-linux" "nested module is indented"
assert_eq "$(hw_module_display_name "$_mdir" docker-gpu "$_names")" "    docker-gpu" "doubly nested module is indented twice"
assert_eq "$(hw_module_display_name "$_mdir" node "$_names")" "node" "sibling module remains top-level"
teardown_env
