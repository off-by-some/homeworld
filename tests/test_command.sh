#!/bin/sh

section "command add creates human-readable launcher"
setup_env
module="$_T_TMP/module"; make_command "$module" greet
gen=$(hw_gen_new)
hw_command_add "$module/commands/greet" greet "$gen" mod
assert_file "$gen/bin/greet" "launcher created"
assert_contains "$gen/bin/greet" HOMEWORLD_COMMAND_DIR "launcher exports command directory"
assert_contains "$gen/bin/greet" 'exec "$HOMEWORLD_COMMAND_DIR/run" "$@"' "launcher uses exec"
result=$("$gen/bin/greet")
assert_eq "$result" greet "launcher runs command"
(hw_command_add "$module/commands/greet" greet "$gen" other) >/dev/null 2>&1
assert_nonzero "$?" "command collision rejected"
teardown_env
