#!/bin/sh

section "generation list, rollback, and gc"
setup_env
one=$(hw_gen_new); hw_gen_write_meta "$one" linux test '' one; hw_gen_activate "$one"
two=$(hw_gen_new); hw_gen_write_meta "$two" linux test '' two; hw_gen_activate "$two"
list=$(hw_gen_list)
printf '%s\n' "$list" | grep -q "$(basename "$two") (current)"; assert_0 "$?" "current marked"
printf '%s\n' "$list" | grep -q "$(basename "$one") (previous)"; assert_0 "$?" "previous marked"
hw_gen_rollback
assert_eq "$(readlink "$(hw_current)")" "$one" "rollback swaps generation"
extra=$(hw_gen_new); hw_atomic_write "$extra/.homeworld/status" abandoned
hw_gen_gc
assert_no_path "$extra" "unreachable generation removed"
assert_dir "$one" "current kept"
assert_dir "$two" "previous kept"
teardown_env

section "legacy and unknown generation schemas"
setup_env
legacy="$HW_DATA/generations/legacy"; mkdir -p "$legacy/.homeworld"
hw_schema_check "$legacy/.homeworld" true
assert_0 "$?" "legacy generation metadata accepted"
printf 999 > "$legacy/.homeworld/schema-version"
(hw_schema_check "$legacy/.homeworld" true) >/dev/null 2>&1
assert_nonzero "$?" "newer unknown schema rejected"
teardown_env
