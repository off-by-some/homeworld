#!/bin/sh

section "activation uses current-relative bindings and rollback"
setup_env
mkdir -p "$HW_DATA/generations" "$HW_STATE/locks"
module_root="$_T_TMP/module"; mkdir -p "$module_root/config"; printf one > "$module_root/config/file"
HOMEWORLD_MODULE_ROOT="$module_root"; export HOMEWORLD_MODULE_ROOT
one=$(hw_gen_new); hw_config_add config/file file "$one" mod; hw_config_link file "$_T_TMP/external" mod "$one"; hw_gen_write_meta "$one" linux test '' mod
hw_gen_activate "$one"
assert_link "$_T_TMP/external" "$(hw_current)/config/mod/file" "binding points through current"
printf two > "$module_root/config/file"
two=$(hw_gen_new); hw_config_add config/file file "$two" mod; hw_config_link file "$_T_TMP/external" mod "$two"; hw_gen_write_meta "$two" linux test '' mod
hw_gen_activate "$two"
assert_eq "$(cat "$_T_TMP/external")" two "new generation visible"
hw_gen_rollback
assert_eq "$(cat "$_T_TMP/external")" one "rollback restores old content"
teardown_env

section "interrupted activation is repaired automatically"
setup_env
module_root="$_T_TMP/module"; mkdir -p "$module_root/config"; printf one > "$module_root/config/file"
HOMEWORLD_MODULE_ROOT="$module_root"; export HOMEWORLD_MODULE_ROOT
one=$(hw_gen_new); hw_config_add config/file file "$one" mod; hw_config_link file "$_T_TMP/external" mod "$one"; hw_gen_write_meta "$one" linux test '' mod; hw_gen_activate "$one"
printf two > "$module_root/config/file"
two=$(hw_gen_new); hw_config_add config/file file "$two" mod; hw_config_link file "$_T_TMP/external" mod "$two"; hw_gen_write_meta "$two" linux test '' mod
(
    HW_TEST_INTERRUPT_AT=after-current
    export HW_TEST_INTERRUPT_AT
    hw_gen_activate "$two"
) >/dev/null 2>&1
code=$?
assert_nonzero "$code" "activation interrupted"
hw_transaction_repair
assert_eq "$(readlink "$(hw_current)")" "$one" "old current restored"
assert_eq "$(cat "$_T_TMP/external")" one "old binding restored"
assert_no_path "$(hw_transaction_dir)" "journal removed after repair"
teardown_env

section "journal schema is validated"
setup_env
mkdir -p "$(hw_transaction_dir)"
printf 999 > "$(hw_transaction_dir)/schema-version"
(hw_transaction_repair) >/dev/null 2>&1
assert_nonzero "$?" "unknown journal schema rejected"
rm -rf "$(hw_transaction_dir)"
teardown_env

section "external TERM triggers transaction recovery"
setup_env
one=$(hw_gen_new); hw_gen_write_meta "$one" linux test '' one; hw_gen_activate "$one"
two=$(hw_gen_new); hw_gen_write_meta "$two" linux test '' two
marker="$_T_TMP/paused"
child="$_T_TMP/activate-child.sh"
cat > "$child" <<EOF2
#!/bin/sh
. "$_LIB_DIR/core.sh"
. "$_LIB_DIR/transaction.sh"
. "$_LIB_DIR/state.sh"
. "$_LIB_DIR/repo.sh"
. "$_LIB_DIR/config.sh"
. "$_LIB_DIR/generation.sh"
HW_DATA='$HW_DATA'; HW_STATE='$HW_STATE'; HW_CACHE='$HW_CACHE'
export HW_DATA HW_STATE HW_CACHE
HW_TEST_PAUSE_AT=after-current
HW_TEST_PAUSE_FILE='$marker'
export HW_TEST_PAUSE_AT HW_TEST_PAUSE_FILE
hw_gen_activate '$two'
EOF2
chmod +x "$child"
sh "$child" >/dev/null 2>&1 &
child_pid=$!
waited=0
while [ ! -f "$marker" ] && [ "$waited" -lt 10 ]; do sleep 1; waited=$((waited + 1)); done
if [ -f "$marker" ]; then
    kill -TERM "$child_pid"
    wait "$child_pid" 2>/dev/null
    assert_nonzero "$?" "TERM stops activation"
    hw_transaction_repair
    assert_eq "$(readlink "$(hw_current)")" "$one" "TERM recovery restores current"
else
    kill -KILL "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    fail "activation reached interruption point"
fi
teardown_env
