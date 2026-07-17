#!/bin/sh

section "state cannot replace repository content"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" upstream
branch=$(git -C "$repo" symbolic-ref --short HEAD)
state_file="$_T_TMP/state-file"; printf mutable > "$state_file"
gen=$(hw_gen_new)
hw_repo_add_to_gen "$repo" app "$gen" "$branch"
repo_path=$(HOMEWORLD_TARGET="$gen" hw_repo_path app)
hw_state_link "$state_file" "$repo_path/file.txt" mod "$gen"
hw_gen_write_meta "$gen" linux test '' mod
(hw_gen_activate "$gen") >/dev/null 2>&1
assert_nonzero "$?" "state replacement of repository file rejected"
teardown_env
