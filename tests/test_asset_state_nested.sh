#!/bin/sh

section "state may occupy absent repository paths"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" upstream
branch=$(git -C "$repo" symbolic-ref --short HEAD)
state_dir="$_T_TMP/state-dir"; mkdir -p "$state_dir"; printf live > "$state_dir/value"
gen=$(hw_gen_new)
hw_repo_add_to_gen "$repo" app "$gen" "$branch"
repo_path=$(HOMEWORLD_TARGET="$gen" hw_repo_path app)
hw_state_link "$state_dir" "$repo_path/runtime" mod "$gen"
hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
assert_eq "$(cat "$(hw_repo_path app)/runtime/value")" live "state can fill absent repository path"
printf changed > "$state_dir/value"
assert_eq "$(cat "$(hw_repo_path app)/runtime/value")" changed "nested state remains mutable"
teardown_env
