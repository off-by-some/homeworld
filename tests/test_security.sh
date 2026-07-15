#!/bin/sh

section "repository canonicalization is conservative and secret-safe"
setup_env
repo="$_T_TMP/real"; make_git_repo "$repo" one; ln -s "$repo" "$_T_TMP/link"
canonical=$(hw_repo_canonical_source "$_T_TMP/link")
assert_eq "$canonical" "$(cd -P "$repo" && pwd)" "local symlink path resolves physically"
assert_not_eq "$(hw_repo_source_id 'git@github.com:x/y.git')" "$(hw_repo_source_id 'ssh://git@github.com/x/y.git')" "different remote syntax remains distinct"
(hw_repo_canonical_source 'https://secret@example.com/repo.git') >"$_T_TMP/out" 2>&1
assert_nonzero "$?" "credential-bearing URL rejected"
if grep -q secret "$_T_TMP/out"; then fail "credential is redacted from errors"; else ok "credential is absent from errors"; fi
(hw_repo_canonical_source 'https://example.com/repo.git?token=secret') >"$_T_TMP/out2" 2>&1
assert_nonzero "$?" "query string rejected"
if grep -q secret "$_T_TMP/out2"; then fail "query secret is redacted"; else ok "query secret is absent from errors"; fi
teardown_env


section "remote default branch parsing accepts Git symref output"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one
bare="$_T_TMP/repo.git"; git clone -q --bare "$repo" "$bare"
remote_head=$(git ls-remote --symref "$bare" HEAD | hw_repo_parse_remote_head)
expected_head=$(git -C "$repo" symbolic-ref HEAD)
assert_eq "$remote_head" "$expected_head" "tab-delimited remote HEAD parsed"
(printf '0123456789abcdef\tHEAD\n' | hw_repo_parse_remote_head) >/dev/null 2>&1
assert_nonzero "$?" "missing symbolic remote HEAD rejected"
teardown_env

section "ref resolution handles default changes and ambiguity"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one
old_branch=$(git -C "$repo" symbolic-ref --short HEAD)
git -C "$repo" checkout -qb stable; printf stable > "$repo/file.txt"; git -C "$repo" commit -qam stable
git -C "$repo" checkout -q "$old_branch"
gen1=$(hw_gen_new); hw_repo_add_to_gen "$repo" tools "$gen1" ''
assert_eq "$(cat "$gen1/repos/tools/file.txt")" one "local symbolic HEAD used as default"
git -C "$repo" checkout -q stable
gen2=$(hw_gen_new); hw_repo_add_to_gen "$repo" tools "$gen2" ''
assert_eq "$(cat "$gen2/repos/tools/file.txt")" stable "default branch change detected"
git -C "$repo" tag "$old_branch"
gen3=$(hw_gen_new)
(hw_repo_add_to_gen "$repo" ambiguous "$gen3" "$old_branch") >/dev/null 2>&1
assert_nonzero "$?" "short branch/tag ambiguity rejected"
teardown_env

section "symlinked destination parents are handled without following the destination"
setup_env
real_parent="$_T_TMP/real-parent"; mkdir -p "$real_parent"; ln -s "$real_parent" "$_T_TMP/link-parent"
module="$_T_TMP/module"; mkdir -p "$module/config"; printf value > "$module/config/file"; HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new); hw_config_link config/file "$_T_TMP/link-parent/file" mod "$gen"; hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
assert_eq "$(cat "$real_parent/file")" value "symlinked parent directory supported"
teardown_env
