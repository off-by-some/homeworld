#!/bin/sh

section "asset overlays compose immutable repository views"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" root
mkdir -p "$repo/conf"
printf upstream-a > "$repo/conf/a"
printf upstream-b > "$repo/conf/b"
git -C "$repo" add .
git -C "$repo" commit -q -m "add conf"
branch=$(git -C "$repo" symbolic-ref --short HEAD)
module="$_T_TMP/module"; mkdir -p "$module/conf/sub"
printf patched > "$module/file.txt"
printf helper > "$module/helper.txt"
printf generated > "$module/generated.txt"
printf asset-a > "$module/conf/a"
printf asset-extra > "$module/conf/sub/extra"
printf asset-hidden > "$module/conf/.hidden"
printf second > "$module/second.txt"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT

gen1=$(hw_gen_new)
hw_repo_add_to_gen "$repo" app "$gen1" "$branch"
repo1=$(HOMEWORLD_TARGET="$gen1" hw_repo_path app)
assert_eq "$(cat "$repo1/file.txt")" root "unprojected repo path is readable"
hw_asset_add file.txt patch "$gen1" mod
hw_asset_link patch "$repo1/file.txt" "$gen1" mod
projected1=$(HOMEWORLD_TARGET="$gen1" hw_repo_path app)
assert_not_eq "$projected1" "$repo1" "repo path switches to composed view"
assert_eq "$(cat "$projected1/file.txt")" patched "pending view uses asset replacement"
checkout1=$(cd "$gen1/repos/app" && pwd -P)
assert_eq "$(cat "$checkout1/file.txt")" root "checkout remains unmodified"
# Regression: resolving repo path freezes a projection. Later links must be able
# to invalidate and rebuild that frozen projection during activation.
hw_asset_add helper.txt helper "$gen1" mod
hw_asset_link helper "$_T_TMP/helper" "$gen1" mod
hw_asset_add generated.txt generated "$gen1" mod
hw_asset_link generated "$repo1/generated.txt" "$gen1" mod
hw_asset_add conf conf "$gen1" mod
hw_asset_link conf "$repo1/conf" "$gen1" mod
hw_gen_write_meta "$gen1" linux test '' mod; hw_gen_activate "$gen1"
active1=$(hw_repo_path app)
assert_eq "$(cat "$active1/file.txt")" patched "active repo path uses composed file overlay"
assert_eq "$(cat "$active1/generated.txt")" generated "asset can add a new file below repo view"
assert_eq "$(cat "$active1/conf/a")" asset-a "directory asset replaces subtree content"
assert_eq "$(cat "$active1/conf/sub/extra")" asset-extra "directory asset exposes nested content"
assert_eq "$(cat "$active1/conf/.hidden")" asset-hidden "directory asset exposes dotfiles"
assert_no_path "$active1/conf/b" "replaced subtree does not leak old repository entries"
assert_eq "$(cat "$_T_TMP/helper")" helper "non-nested asset still links externally"
assert_eq "$(cat "$checkout1/conf/a")" upstream-a "activation does not patch checkout subtree"

gen2=$(hw_gen_new)
hw_repo_add_to_gen "$repo" app "$gen2" "$branch"
repo2=$(HOMEWORLD_TARGET="$gen2" hw_repo_path app)
hw_asset_add second.txt patch "$gen2" mod
hw_asset_link patch "$repo2/file.txt" "$gen2" mod
hw_gen_write_meta "$gen2" linux test '' mod; hw_gen_activate "$gen2"
assert_eq "$(cat "$(hw_repo_path app)/file.txt")" second "new generation selects its own asset overlay"
hw_gen_rollback
assert_eq "$(cat "$(hw_repo_path app)/file.txt")" patched "rollback restores matching asset overlay"
teardown_env
