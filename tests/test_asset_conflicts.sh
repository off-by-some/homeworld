#!/bin/sh
section "ambiguous or unsafe nested asset overlays are rejected"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" upstream
mkdir -p "$repo/subdir"
printf original > "$repo/subdir/nested"
git -C "$repo" add .
git -C "$repo" commit -q -m "add nested"
branch=$(git -C "$repo" symbolic-ref --short HEAD)
module="$_T_TMP/module"; mkdir -p "$module"
printf top > "$module/top"
printf child > "$module/child"
printf other > "$module/other"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT

gen=$(hw_gen_new)
hw_repo_add_to_gen "$repo" app "$gen" "$branch"
repo_path=$(HOMEWORLD_TARGET="$gen" hw_repo_path app)
hw_asset_add top top "$gen" mod
hw_asset_link top "$repo_path/subdir" "$gen" mod
hw_asset_add child child "$gen" mod
hw_asset_link child "$repo_path/subdir/nested" "$gen" mod
hw_gen_write_meta "$gen" linux test '' mod
(hw_gen_activate "$gen") >/dev/null 2>&1
assert_nonzero "$?" "ancestor and descendant overlays conflict"

gen2=$(hw_gen_new)
hw_repo_add_to_gen "$repo" app "$gen2" "$branch"
repo2=$(HOMEWORLD_TARGET="$gen2" hw_repo_path app)
hw_asset_add top top "$gen2" mod
hw_asset_link top "$repo2/file.txt" "$gen2" mod
hw_asset_add other other "$gen2" mod
hw_asset_link other "$repo2/file.txt" "$gen2" mod
hw_gen_write_meta "$gen2" linux test '' mod
(hw_gen_activate "$gen2") >/dev/null 2>&1
assert_nonzero "$?" "different assets cannot claim the same nested destination"

gen3=$(hw_gen_new)
hw_repo_add_to_gen "$repo" app "$gen3" "$branch"
repo3=$(HOMEWORLD_TARGET="$gen3" hw_repo_path app)
hw_asset_add child child "$gen3" mod
hw_asset_link child "$repo3/file.txt/child" "$gen3" mod
hw_gen_write_meta "$gen3" linux test '' mod
(hw_gen_activate "$gen3") >/dev/null 2>&1
assert_nonzero "$?" "asset overlay cannot cross repository file as directory"
teardown_env
