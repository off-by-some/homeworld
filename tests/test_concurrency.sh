#!/bin/sh

section "pending generations are garbage-collection roots"
setup_env
pending=$(hw_gen_new)
checkout="$HW_DATA/git/checkouts/source/commit"; mkdir -p "$checkout"
mkdir -p "$pending/.homeworld/repo-manifest/tools"
hw_schema_write "$pending/.homeworld/repo-manifest"; hw_schema_write "$pending/.homeworld/repo-manifest/tools"
hw_atomic_write "$pending/.homeworld/repo-manifest/tools/source-id" source
hw_atomic_write "$pending/.homeworld/repo-manifest/tools/sha" commit
hw_gen_gc
assert_dir "$pending" "pending generation retained"
assert_dir "$checkout" "pending checkout retained"
teardown_env

section "global generation lock serializes GC"
setup_env
lock=$(hw_global_lock_dir); marker="$_T_TMP/locked"; child="$_T_TMP/lock.sh"
cat > "$child" <<EOF2
#!/bin/sh
. "$_LIB_DIR/core.sh"
HW_DATA='$HW_DATA'; HW_STATE='$HW_STATE'; HW_CACHE='$HW_CACHE'; export HW_DATA HW_STATE HW_CACHE
hw_lock_acquire '$lock' test
: > '$marker'
sleep 2
hw_lock_release '$lock'
EOF2
sh "$child" & child_pid=$!
waited=0; while [ ! -f "$marker" ] && [ "$waited" -lt 10 ]; do sleep 1; waited=$((waited + 1)); done
start=$(date +%s); hw_gen_gc; end=$(date +%s)
wait "$child_pid"
[ $((end - start)) -ge 1 ] && ok "GC waits for active generation transaction" || fail "GC should wait for generation lock"
teardown_env

section "repository cleanup uses the source lock"
setup_env
source_id=abc123; lock=$(hw_repo_source_lock "$source_id")
mkdir -p "$(hw_mirrors_dir)/$source_id.git" "$(hw_orphaned_dir)/$source_id"
hw_schema_write "$(hw_orphaned_dir)/$source_id"; hw_atomic_write "$(hw_orphaned_dir)/$source_id/orphaned-at" 0
marker="$_T_TMP/repo-locked"; child="$_T_TMP/repo-lock.sh"
cat > "$child" <<EOF2
#!/bin/sh
. "$_LIB_DIR/core.sh"
HW_DATA='$HW_DATA'; HW_STATE='$HW_STATE'; HW_CACHE='$HW_CACHE'; export HW_DATA HW_STATE HW_CACHE
hw_lock_acquire '$lock' repository
: > '$marker'
sleep 2
hw_lock_release '$lock'
EOF2
sh "$child" & child_pid=$!
waited=0; while [ ! -f "$marker" ] && [ "$waited" -lt 10 ]; do sleep 1; waited=$((waited + 1)); done
HW_MIRROR_GRACE_DAYS=0; export HW_MIRROR_GRACE_DAYS
start=$(date +%s); hw_repo_gc_locked; end=$(date +%s)
wait "$child_pid"
[ $((end - start)) -ge 1 ] && ok "mirror expiration waits for source lock" || fail "repo GC should wait for source lock"
teardown_env
