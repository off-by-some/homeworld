#!/bin/sh

section "named state rebinding is automatic and non-generational"
setup_env
state1="$_T_TMP/state one"; state2="$_T_TMP/state two"; mkdir -p "$state1" "$state2"
hw_state_bind_update app "$state1"
module="$_T_TMP/module"; mkdir -p "$module"; HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new); hw_state_link app "$_T_TMP/external" mod "$gen"; hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
assert_link "$_T_TMP/external" "$(hw_state_target_link app)" "named state uses stable resolver"
assert_link "$(hw_state_target_link app)" "$state1" "resolver points to first state target"
hw_state_bind_update app "$state2"
assert_link "$_T_TMP/external" "$(hw_state_target_link app)" "state destination remains stable after rebind"
assert_link "$(hw_state_target_link app)" "$state2" "state rebind updates resolver"
assert_dir "$state1" "old state target preserved"
assert_dir "$state2" "new state target preserved"
(hw_gen_rollback) >/dev/null 2>&1
# No previous generation exists; failed rollback must not change machine binding.
assert_link "$_T_TMP/external" "$(hw_state_target_link app)" "failed rollback keeps stable state destination"
assert_link "$(hw_state_target_link app)" "$state2" "failed rollback does not rebind state"
teardown_env

section "state failures are non-destructive"
setup_env
(hw_state_bind_update missing "$_T_TMP/nope") >/dev/null 2>&1
assert_nonzero "$?" "missing state target rejected"
mkdir -p "$_T_TMP/dir"; hw_state_bind_update app "$_T_TMP/dir"
assert_eq "$(hw_state_bind_read app)" "$_T_TMP/dir" "binding recorded"
rm -rf "$_T_TMP/dir"; printf file > "$_T_TMP/dir"
module="$_T_TMP/module"; mkdir -p "$module"; HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new); hw_state_link app "$_T_TMP/external" mod "$gen"; hw_gen_write_meta "$gen" linux test '' mod
(hw_gen_activate "$gen") >/dev/null 2>&1
assert_nonzero "$?" "state type mismatch rejected before activation"
assert_no_path "$_T_TMP/external" "no partial state link"
teardown_env

section "nested state is composed inside a linked repository view"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
home="$_T_TMP/home"; mkdir -p "$home"
state1="$_T_TMP/versions one"; state2="$_T_TMP/versions two"; mkdir -p "$state1" "$state2"
printf 'first\n' > "$state1/marker"; printf 'second\n' > "$state2/marker"
hw_state_bind_update pyenv-versions "$state1"
module="$_T_TMP/module"; mkdir -p "$module"; HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT

gen1=$(hw_gen_new)
hw_repo_add_to_gen "$repo" pyenv "$gen1" "$branch"
hw_repo_link pyenv "$home/.pyenv" "$gen1" mod
hw_state_link pyenv-versions "$home/.pyenv/versions" mod "$gen1"
hw_gen_write_meta "$gen1" linux test '' mod
hw_gen_activate "$gen1"
assert_eq "$(cat "$home/.pyenv/file.txt")" one "repository view exposes checkout content"
assert_eq "$(cat "$home/.pyenv/versions/marker")" first "nested state is exposed inside repository view"
assert_link "$home/.pyenv/versions" "$(hw_state_target_link pyenv-versions)" "nested named state uses stable resolver"
checkout1=$(cd "$gen1/repos/pyenv" && pwd -P)
assert_no_path "$checkout1/versions" "immutable checkout is not modified"

hw_state_bind_update pyenv-versions "$state2"
assert_eq "$(cat "$home/.pyenv/versions/marker")" second "nested state rebinding is automatic"

git_commit "$repo" file.txt two
gen2=$(hw_gen_new)
hw_repo_add_to_gen "$repo" pyenv "$gen2" "$branch"
hw_repo_link pyenv "$home/.pyenv" "$gen2" mod
hw_state_link pyenv-versions "$home/.pyenv/versions" mod "$gen2"
hw_gen_write_meta "$gen2" linux test '' mod
hw_gen_activate "$gen2"
assert_eq "$(cat "$home/.pyenv/file.txt")" two "new generation advances repository content"
assert_eq "$(cat "$home/.pyenv/versions/marker")" second "new generation preserves current state binding"
hw_gen_rollback
assert_eq "$(cat "$home/.pyenv/file.txt")" one "rollback restores repository revision"
assert_eq "$(cat "$home/.pyenv/versions/marker")" second "rollback does not roll back named state"
teardown_env

section "nested state conflicts fail before activation"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
home="$_T_TMP/home"; mkdir -p "$home"
state="$_T_TMP/versions"; mkdir -p "$state"
hw_state_bind_update pyenv-versions "$state"
module="$_T_TMP/module"; mkdir -p "$module"; HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT

gen1=$(hw_gen_new)
hw_repo_add_to_gen "$repo" pyenv "$gen1" "$branch"
hw_repo_link pyenv "$home/.pyenv" "$gen1" mod
hw_state_link pyenv-versions "$home/.pyenv/versions" mod "$gen1"
hw_gen_write_meta "$gen1" linux test '' mod
hw_gen_activate "$gen1"
old_current=$(readlink "$(hw_current)")
mkdir -p "$repo/versions"; printf upstream > "$repo/versions/README"; git -C "$repo" add .; git -C "$repo" commit -q -m 'add versions path'
gen2=$(hw_gen_new)
hw_repo_add_to_gen "$repo" pyenv "$gen2" "$branch"
hw_repo_link pyenv "$home/.pyenv" "$gen2" mod
hw_state_link pyenv-versions "$home/.pyenv/versions" mod "$gen2"
hw_gen_write_meta "$gen2" linux test '' mod
(hw_gen_activate "$gen2") >/dev/null 2>&1
assert_nonzero "$?" "upstream path collision is rejected"
assert_eq "$(readlink "$(hw_current)")" "$old_current" "collision leaves current generation unchanged"
assert_eq "$(cat "$home/.pyenv/file.txt")" one "collision leaves active repository usable"
teardown_env

section "nested state topology is unambiguous"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
mkdir -p "$repo/versions"; printf upstream > "$repo/versions/README"; git -C "$repo" add .; git -C "$repo" commit -q -m 'add versions directory'
home="$_T_TMP/home"; mkdir -p "$home"
module="$_T_TMP/module"; mkdir -p "$module"; HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT

gen=$(hw_gen_new)
hw_repo_add_to_gen "$repo" pyenv "$gen" "$branch"
hw_repo_link pyenv "$home/.pyenv" "$gen" mod
hw_gen_write_meta "$gen" linux test '' mod
hw_gen_activate "$gen"
(hw_state_bind_update circular "$home/.pyenv/versions") >/dev/null 2>&1
assert_nonzero "$?" "state storage beneath a managed root is rejected"
assert_no_path "$(hw_state_name_dir circular)" "rejected circular binding writes no metadata"
teardown_env

section "identical nested state consumers share one projection"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
home="$_T_TMP/home"; mkdir -p "$home"
state="$_T_TMP/versions"; mkdir -p "$state"; printf shared > "$state/marker"
hw_state_bind_update pyenv-versions "$state"
module="$_T_TMP/module"; mkdir -p "$module"; HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT

gen=$(hw_gen_new)
hw_repo_add_to_gen "$repo" pyenv "$gen" "$branch"
hw_repo_link pyenv "$home/.pyenv" "$gen" repo-module
hw_state_link pyenv-versions "$home/.pyenv/versions" first-module "$gen"
hw_state_link pyenv-versions "$home/.pyenv/versions" second-module "$gen"
hw_gen_write_meta "$gen" linux test '' 'repo-module first-module second-module'
hw_gen_activate "$gen"
assert_eq "$(cat "$home/.pyenv/versions/marker")" shared "identical nested consumers are deduplicated"
teardown_env

section "older direct named-state links migrate automatically"
setup_env
state="$_T_TMP/state"; mkdir -p "$state"
hw_state_bind_update app "$state"
module="$_T_TMP/module"; mkdir -p "$module"; HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT

gen1=$(hw_gen_new); hw_state_link app "$_T_TMP/external" mod "$gen1"; hw_gen_write_meta "$gen1" linux test '' mod; hw_gen_activate "$gen1"
# Simulate the 2.0.1 layout, where named state destinations pointed directly
# at the resolved path rather than through the stable resolver.
hw_symlink_replace "$state" "$_T_TMP/external"
gen2=$(hw_gen_new); hw_state_link app "$_T_TMP/external" mod "$gen2"; hw_gen_write_meta "$gen2" linux test '' mod; hw_gen_activate "$gen2"
assert_link "$_T_TMP/external" "$(hw_state_target_link app)" "legacy direct state link migrates during activation"
teardown_env
