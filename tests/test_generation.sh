#!/bin/sh
# test_generation.sh — generation lifecycle: create, activate, rollback, gc, repair

section "hw_gen_new — directory structure"

setup_env
_gen=$(hw_gen_new)
assert_dir "$_gen"            "generation directory created"
assert_dir "$_gen/assets"     "assets/ present"
assert_dir "$_gen/bin"        "bin/ present"
assert_dir "$_gen/commands"   "commands/ present"
assert_dir "$_gen/config"     "config/ present"
assert_dir "$_gen/.homeworld" ".homeworld/ present"
teardown_env

section "hw_gen_write_meta — metadata fields"

setup_env
_gen=$(hw_gen_new)
hw_gen_write_meta "$_gen" "linux" "manjaro" "pacman" "root worker"
assert_file "$_gen/.homeworld/platform"         "platform written"
assert_file "$_gen/.homeworld/distro"           "distro written"
assert_file "$_gen/.homeworld/package-provider" "provider written"
assert_file "$_gen/.homeworld/installed-modules" "modules written"
assert_file "$_gen/.homeworld/created-at"       "timestamp written"
assert_eq "$(cat "$_gen/.homeworld/platform")" "linux"   "platform value"
assert_eq "$(cat "$_gen/.homeworld/distro")"   "manjaro" "distro value"
teardown_env

section "hw_gen_activate — first activation"

setup_env
_gen=$(hw_gen_new)
hw_gen_activate "$_gen"
assert_link "$(hw_current)" "$_gen" "current symlink points to new generation"
assert_no_path "$_gen/.homeworld/activation-journal" "journal removed on clean activation"
teardown_env

section "hw_gen_activate — updates previous on second activation"

setup_env
_gen1=$(hw_gen_new); hw_gen_activate "$_gen1"
_gen2=$(hw_gen_new); hw_gen_activate "$_gen2"
assert_link "$(hw_current)"  "$_gen2" "current -> gen2"
assert_link "$(hw_previous)" "$_gen1" "previous -> gen1"
teardown_env

section "hw_gen_rollback — swaps current and previous"

setup_env
_gen1=$(hw_gen_new); hw_gen_activate "$_gen1"
_gen2=$(hw_gen_new); hw_gen_activate "$_gen2"
hw_gen_rollback
assert_link "$(hw_current)"  "$_gen1" "current rolls back to gen1"
assert_link "$(hw_previous)" "$_gen2" "previous now holds gen2"
teardown_env

section "hw_gen_rollback — rolling back again re-applies the forward"

setup_env
_gen1=$(hw_gen_new); hw_gen_activate "$_gen1"
_gen2=$(hw_gen_new); hw_gen_activate "$_gen2"
hw_gen_rollback
hw_gen_rollback  # second rollback should undo the first
assert_link "$(hw_current)" "$_gen2" "double rollback returns to gen2"
teardown_env

section "hw_gen_rollback — failure cases"

setup_env
( hw_gen_rollback ) 2>/dev/null
assert_nonzero $? "fails with no active generation"
teardown_env

setup_env
_gen1=$(hw_gen_new); hw_gen_activate "$_gen1"
( hw_gen_rollback ) 2>/dev/null
assert_nonzero $? "fails when no previous generation exists"
teardown_env

section "hw_gen_list — marks current and previous"

setup_env
_gen1=$(hw_gen_new); hw_gen_activate "$_gen1"
_gen2=$(hw_gen_new); hw_gen_activate "$_gen2"
_gen3=$(hw_gen_new); hw_gen_activate "$_gen3"
_listing=$(hw_gen_list)
printf '%s' "$_listing" | grep -q "$(basename "$_gen3") (current)"; assert_0 $? "marks current"
printf '%s' "$_listing" | grep -q "$(basename "$_gen2") (previous)"; assert_0 $? "marks previous"
printf '%s' "$_listing" | grep -q "$(basename "$_gen1")$";           assert_0 $? "gen1 has no marker"
teardown_env

section "hw_gen_gc — removes unreferenced generations"

setup_env
_gen1=$(hw_gen_new); hw_gen_activate "$_gen1"
_gen2=$(hw_gen_new); hw_gen_activate "$_gen2"
_gen3=$(hw_gen_new); hw_gen_activate "$_gen3"
# gen1 is now unreferenced (current=gen3, previous=gen2)
hw_gen_gc
assert_dir    "$_gen3" "gc keeps current generation"
assert_dir    "$_gen2" "gc keeps previous generation"
assert_no_path "$_gen1" "gc removes unreferenced generation"
teardown_env

section "hw_gen_repair — cleans up stale pending symlinks"

setup_env
# Simulate crash that left pending-current behind
ln -s "$HW_DATA/generations/stale" "$HW_DATA/pending-current"
hw_gen_repair 2>/dev/null
assert_0 $?  "repair exits cleanly"
assert_no_path "$HW_DATA/pending-current" "stale pending-current removed"
teardown_env

section "interrupted activation — journal survives, state is not corrupted"

# If we crash between writing the journal and completing the symlink swap,
# the journal file is left behind. hw_gen_repair does not attempt to replay
# or undo partial config link creation (that would require knowing exactly
# which steps completed). The journal serves as a diagnostic artifact.
# The important guarantee is that the existing current symlink is untouched.

setup_env
_gen1=$(hw_gen_new); hw_gen_activate "$_gen1"
_gen2=$(hw_gen_new)

# Write journal (step 1 of activation) but stop before the symlink swap
printf '%s\n' "$_gen2" > "$_gen2/.homeworld/activation-journal"
# current still points to gen1

hw_gen_repair 2>/dev/null
assert_0 $? "repair does not crash after interrupted activation"
assert_link "$(hw_current)" "$_gen1" "current untouched after interrupted activation"
assert_file "$_gen2/.homeworld/activation-journal" "journal preserved for diagnosis"

teardown_env
