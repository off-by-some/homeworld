#!/bin/sh

section "repository checkout is isolated from mirror"
setup_env
repo="$_T_TMP/source repo"; make_git_repo "$repo" one
branch=$(git -C "$repo" symbolic-ref --short HEAD)
gen=$(hw_gen_new)
hw_repo_add_to_gen "$repo" tools "$gen" "$branch"
manifest="$gen/.homeworld/repo-manifest/tools"
id=$(cat "$manifest/source-id"); sha=$(cat "$manifest/sha")
mirror=$(hw_repo_mirror_path "$id"); checkout=$(hw_repo_checkout_path "$id" "$sha")
assert_dir "$mirror" "mirror created"
assert_dir "$checkout" "checkout created"
mirror_object=$(find "$mirror/objects" -type f | sed -n '1p')
checkout_object=$(find "$checkout/.git/objects" -type f | sed -n '1p')
if [ -n "$mirror_object" ] && [ -n "$checkout_object" ]; then
    mirror_inode=$(ls -i "$mirror_object" | awk '{print $1}')
    checkout_inode=$(ls -i "$checkout_object" | awk '{print $1}')
    assert_not_eq "$mirror_inode" "$checkout_inode" "mirror and checkout objects do not share inodes"
else
    fail "object files available for inode comparison"
fi
mirror_mode_before=$(ls -ld "$mirror/objects" | awk '{print $1}')
chmod -R a-w "$checkout"
mirror_mode_after=$(ls -ld "$mirror/objects" | awk '{print $1}')
assert_eq "$mirror_mode_after" "$mirror_mode_before" "freezing checkout does not change mirror permissions"
git_commit "$repo" second two
hw_repo_fetch_source "$repo" "$id"
assert_0 "$?" "fetch works after checkout freeze"
git --git-dir="$mirror" repack -ad >/dev/null 2>&1
assert_0 "$?" "mirror repack works"
git --git-dir="$mirror" prune >/dev/null 2>&1
assert_eq "$(cat "$checkout/file.txt")" one "mirror maintenance leaves checkout intact"
chmod -R u+w "$checkout"; rm -rf "$checkout"
git --git-dir="$mirror" fsck --no-dangling >/dev/null 2>&1
assert_0 "$?" "checkout deletion leaves mirror intact"
teardown_env

section "repository declarations pin commits and permit automatic source changes"
setup_env
repo1="$_T_TMP/one"; repo2="$_T_TMP/two"; make_git_repo "$repo1" one; make_git_repo "$repo2" other
branch1=$(git -C "$repo1" symbolic-ref --short HEAD); branch2=$(git -C "$repo2" symbolic-ref --short HEAD)
gen1=$(hw_gen_new); hw_repo_add_to_gen "$repo1" tools "$gen1" "$branch1"
sha1=$(cat "$gen1/.homeworld/repo-manifest/tools/sha")
gen2=$(hw_gen_new); hw_repo_add_to_gen "$repo2" tools "$gen2" "$branch2"
sha2=$(cat "$gen2/.homeworld/repo-manifest/tools/sha")
assert_not_eq "$(cat "$gen1/.homeworld/repo-manifest/tools/source-id")" "$(cat "$gen2/.homeworld/repo-manifest/tools/source-id")" "changed source gets independent cache"
assert_eq "$(cat "$gen1/repos/tools/file.txt")" one "old realization remains"
assert_eq "$(cat "$gen2/repos/tools/file.txt")" other "new realization created"
assert_not_eq "$sha1" "$sha2" "different commits recorded"
teardown_env

section "repository source and ref validation"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; gen=$(hw_gen_new)
(hw_repo_add_to_gen 'https://token@example.com/repo.git' bad "$gen" main) >/dev/null 2>&1
assert_nonzero "$?" "embedded credentials rejected"
(hw_repo_add_to_gen "$repo" bad "$gen" '--upload-pack=x') >/dev/null 2>&1
assert_nonzero "$?" "option-shaped ref rejected"
blob=$(printf blob | git -C "$repo" hash-object -w --stdin)
(hw_repo_add_to_gen "$repo" blob "$gen" "$blob") >/dev/null 2>&1
assert_nonzero "$?" "non-commit object rejected"
teardown_env

section "repository update intent comes from current manifest"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
gen=$(hw_gen_new); hw_repo_add_to_gen "$repo" tools "$gen" "$branch"; hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
git_commit "$repo" second two
hw_repo_update_current tools
assert_0 "$?" "current repository fetch succeeds"
assert_eq "$(cat "$(hw_current)/repos/tools/file.txt")" one "fetch does not mutate active checkout"
teardown_env

section "test cleanup removes frozen checkouts"
setup_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one
branch=$(git -C "$repo" symbolic-ref --short HEAD)
gen=$(hw_gen_new); hw_repo_add_to_gen "$repo" tools "$gen" "$branch"
temporary_root=$_T_TMP
teardown_env
assert_no_path "$temporary_root" "temporary root removed after read-only checkout"
