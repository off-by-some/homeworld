#!/bin/sh
# framework.sh — test assertions, environment isolation, and fixture helpers.
#
# Designed to be sourced into a test runner after the homeworld lib is loaded.
# Color variables from core.sh are available here; no external deps required.

_T_PASS=0
_T_FAIL=0

# ---- assertion primitives ------------------------------------------------

ok() {
    _T_PASS=$(expr "$_T_PASS" + 1)
    printf '  %sOK%s   %s\n' "$_HW_C_OK" "$_HW_C_RST" "$1" >&2
}

fail() {
    _T_FAIL=$(expr "$_T_FAIL" + 1)
    printf '  %sFAIL%s %s\n' "$_HW_C_ERR" "$_HW_C_RST" "$1" >&2
}

# assert_eq actual expected [label]
assert_eq() {
    if [ "$1" = "$2" ]; then
        ok "${3:-eq: '$1'}"
    else
        fail "${3:-assert_eq}: expected '$2', got '$1'"
    fi
}

# assert_0 exit_code [label] — the previous command must have succeeded
assert_0() {
    if [ "$1" = "0" ]; then
        ok "${2:-succeeded}"
    else
        fail "${2:-succeeded}: got exit code $1"
    fi
}

# assert_nonzero exit_code [label] — the previous command must have failed.
# Exit code 127 (command not found) is treated as a test infrastructure failure,
# not a valid domain failure, so it always fails the assertion.
assert_nonzero() {
    if [ "$1" = "0" ]; then
        fail "${2:-should have failed}: got exit code 0"
    elif [ "$1" = "127" ]; then
        fail "${2:-should have failed}: command not found (127) — function may not be defined"
    else
        ok "${2:-failed as expected}"
    fi
}

assert_file() {
    if [ -f "$1" ]; then
        ok "${2:-file exists: $(basename "$1")}"
    else
        fail "${2:-file missing: $1}"
    fi
}

assert_dir() {
    if [ -d "$1" ]; then
        ok "${2:-dir exists: $(basename "$1")}"
    else
        fail "${2:-dir missing: $1}"
    fi
}

# assert_no_path — neither a file, directory, nor a dangling symlink
assert_no_path() {
    if [ ! -e "$1" ] && [ ! -L "$1" ]; then
        ok "${2:-absent: $(basename "$1")}"
    else
        fail "${2:-expected absent: $1}"
    fi
}

# assert_link link expected_target [label]
assert_link() {
    _al_got=$(readlink "$1" 2>/dev/null)
    if [ -L "$1" ] && [ "$_al_got" = "$2" ]; then
        ok "${3:-symlink: $(basename "$1") -> $(basename "$2")}"
    else
        fail "${3:-symlink}: expected $1 -> $2, got -> ${_al_got:-(not a symlink)}"
    fi
}

# assert_contains file string [label] — file must contain the string
assert_contains() {
    if grep -qF "$2" "$1" 2>/dev/null; then
        ok "${3:-contains: $2}"
    else
        fail "${3:-missing in $(basename "$1")}: '$2'"
    fi
}

# section name — heading for a group of related tests
section() {
    printf '\n%s%s%s\n' "$_HW_C_BOLD" "$1" "$_HW_C_RST" >&2
}

# t_summary — print final totals; return 1 if any tests failed
t_summary() {
    printf '\n'
    if [ "$_T_FAIL" = "0" ]; then
        printf '%s%d passed, 0 failed%s\n' "$_HW_C_OK" "$_T_PASS" "$_HW_C_RST" >&2
    else
        printf '%d passed, %s%d failed%s\n' \
            "$_T_PASS" "$_HW_C_ERR" "$_T_FAIL" "$_HW_C_RST" >&2
        return 1
    fi
}

# ---- environment isolation -----------------------------------------------
# Unit tests call library functions directly, so they need HW_DATA etc. to
# point at a throw-away temp directory, not the real user state.

_T_TMP=""
_T_OLD_DATA=""; _T_OLD_STATE=""; _T_OLD_CACHE=""; _T_OLD_CONFIG=""


# Make temporary trees removable after tests create read-only repository
# realizations. Only directories need their owner write bit restored for rm to
# unlink their contents. find does not follow symlinked directories here, so
# external state and managed destinations are not modified.
test_make_tree_removable() {
    _tmtr_root=$1
    [ -d "$_tmtr_root" ] || return 0
    find "$_tmtr_root" -type d -exec chmod u+rwx {} + 2>/dev/null || true
}

# setup_env — redirect HW_* paths to an isolated tmpdir for the current test.
# Always pair with teardown_env.
setup_env() {
    _T_TMP=$(mktemp -d)
    _T_OLD_DATA="${HW_DATA:-}"
    _T_OLD_STATE="${HW_STATE:-}"
    _T_OLD_CACHE="${HW_CACHE:-}"
    _T_OLD_CONFIG="${XDG_CONFIG_HOME:-}"
    HW_DATA="$_T_TMP/data"
    HW_STATE="$_T_TMP/state"
    HW_CACHE="$_T_TMP/cache"
    XDG_CONFIG_HOME="$_T_TMP/config"
    export HW_DATA HW_STATE HW_CACHE XDG_CONFIG_HOME
    mkdir -p "$HW_DATA/generations" "$HW_STATE/locks" "$HW_CACHE" "$XDG_CONFIG_HOME"
}

teardown_env() {
    HW_DATA="$_T_OLD_DATA"
    HW_STATE="$_T_OLD_STATE"
    HW_CACHE="$_T_OLD_CACHE"
    XDG_CONFIG_HOME="$_T_OLD_CONFIG"
    export HW_DATA HW_STATE HW_CACHE XDG_CONFIG_HOME
    test_make_tree_removable "$_T_TMP"
    rm -rf "$_T_TMP"
    _T_TMP=""
}

# CLI tests invoke the homeworld binary as a subprocess. They pass XDG vars
# so the subprocess's core.sh builds the same isolated paths.
_T_XDG=""

setup_cli_env() {
    _T_TMP=$(mktemp -d)
    _T_XDG="$_T_TMP"
    _T_OLD_CONFIG="${XDG_CONFIG_HOME:-}"
    XDG_CONFIG_HOME="$_T_XDG/xdg/config"
    export XDG_CONFIG_HOME
    mkdir -p \
        "$_T_XDG/xdg/data" \
        "$_T_XDG/xdg/state" \
        "$_T_XDG/xdg/cache" \
        "$_T_XDG/xdg/config" \
        "$_T_XDG/home"
}

teardown_cli_env() {
    test_make_tree_removable "$_T_TMP"
    rm -rf "$_T_TMP"
    XDG_CONFIG_HOME="$_T_OLD_CONFIG"
    export XDG_CONFIG_HOME
    _T_TMP=""
    _T_XDG=""
}

# hw_cli args... — run homeworld with isolated XDG environment
hw_cli() {
    XDG_DATA_HOME="$_T_XDG/xdg/data" \
    XDG_STATE_HOME="$_T_XDG/xdg/state" \
    XDG_CACHE_HOME="$_T_XDG/xdg/cache" \
    XDG_CONFIG_HOME="$_T_XDG/xdg/config" \
    HOME="$_T_XDG/home" \
        homeworld "$@"
}

# hw_data_dir — resolve HW_DATA path for the current CLI test
hw_data_dir() {
    printf '%s/xdg/data/homeworld' "$_T_XDG"
}

# ---- fixture builders ----------------------------------------------------

# make_module dir name [extra_manifest_lines]
# Create a minimal .homeworld-module manifest in dir.
make_module() {
    _mm_dir="$1"; _mm_name="$2"; _mm_extra="${3:-}"
    mkdir -p "$_mm_dir"
    printf 'HOMEWORLD_MODULE_NAME="%s"\n' "$_mm_name" > "$_mm_dir/.homeworld-module"
    printf 'HOMEWORLD_DESCRIPTION="test module %s"\n' "$_mm_name" >> "$_mm_dir/.homeworld-module"
    [ -n "$_mm_extra" ] && printf '%s\n' "$_mm_extra" >> "$_mm_dir/.homeworld-module"
}

# make_command module_dir cmd_name
# Create a commands/<cmd>/run file (executable).
make_command() {
    _mc_dir="$1"; _mc_cmd="$2"
    mkdir -p "$_mc_dir/commands/$_mc_cmd"
    printf '#!/bin/sh\nprintf "%s\\n" "%s"\n' "$_mc_cmd" "$_mc_cmd" \
        > "$_mc_dir/commands/$_mc_cmd/run"
    chmod +x "$_mc_dir/commands/$_mc_cmd/run"
}

# make_config module_dir filename [content]
# Create a config/<filename> file inside the module.
make_config() {
    _cfg_dir="$1"; _cfg_file="$2"; _cfg_content="${3:-# config}"
    mkdir -p "$_cfg_dir/config"
    printf '%s\n' "$_cfg_content" > "$_cfg_dir/config/$_cfg_file"
}

# make_git_repo dir [initial_content]
# Initialise a local git repository with a single commit containing file.txt.
make_git_repo() {
    _mgr_dir="$1"; _mgr_content="${2:-v1}"
    mkdir -p "$_mgr_dir"
    git -C "$_mgr_dir" init -q
    git -C "$_mgr_dir" config user.email "test@homeworld.local"
    git -C "$_mgr_dir" config user.name "Homeworld Test"
    printf '%s\n' "$_mgr_content" > "$_mgr_dir/file.txt"
    git -C "$_mgr_dir" add .
    git -C "$_mgr_dir" commit -q -m "initial commit"
}

# git_commit dir filename content
# Add or overwrite filename in a git repo and commit it.
git_commit() {
    _gc_dir="$1"; _gc_file="$2"; _gc_content="$3"
    printf '%s\n' "$_gc_content" > "$_gc_dir/$_gc_file"
    git -C "$_gc_dir" add .
    git -C "$_gc_dir" commit -q -m "add $_gc_file"
}

make_asset() {
    _ma_dir=$1; _ma_name=$2; _ma_content=${3:-asset}
    mkdir -p "$_ma_dir/assets"
    printf '%s\n' "$_ma_content" > "$_ma_dir/assets/$_ma_name"
}

make_state_dir() {
    mkdir -p "$1"
    [ $# -lt 2 ] || printf 'state\n' > "$1/$2"
}

assert_not_eq() {
    if [ "$1" != "$2" ]; then ok "${3:-values differ}"; else fail "${3:-values should differ}"; fi
}

assert_read_only() {
    if [ ! -w "$1" ]; then ok "${2:-read-only: $1}"; else fail "${2:-expected read-only: $1}"; fi
}
