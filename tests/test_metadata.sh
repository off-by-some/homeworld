#!/bin/sh

section "derived cache metadata is never required"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
gen=$(hw_gen_new); hw_repo_add_to_gen "$repo" tools "$gen" "$branch"; hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
rm -rf "$HW_DATA/git/cache-index"
git_commit "$repo" next two
hw_repo_update_current tools
assert_0 "$?" "repo update works with cache index absent"
hw_gen_gc
assert_0 "$?" "GC works with cache index absent"
teardown_env

section "metadata structures reject unknown schemas"
setup_env
gen=$(hw_gen_new)
mkdir -p "$gen/.homeworld/managed-links"; printf 999 > "$gen/.homeworld/managed-links/schema-version"
(hw_managed_link_validate '' "$gen") >/dev/null 2>&1
assert_nonzero "$?" "managed-link schema checked"
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
gen2=$(hw_gen_new); hw_repo_add_to_gen "$repo" tools "$gen2" "$branch"; hw_gen_write_meta "$gen2" linux test '' mod; hw_gen_activate "$gen2"
printf 999 > "$gen2/.homeworld/repo-manifest/schema-version"
(hw_repo_update_current tools) >/dev/null 2>&1
assert_nonzero "$?" "repo-manifest schema checked"
mkdir -p "$(hw_state_name_dir app)"; printf 999 > "$(hw_state_name_dir app)/schema-version"
(hw_state_bind_read app) >/dev/null 2>&1
assert_nonzero "$?" "state-binding schema checked"
teardown_env
