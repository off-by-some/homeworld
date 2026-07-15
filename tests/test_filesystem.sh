#!/bin/sh

section "data, state, and external destinations may use different filesystems"
base=$(mktemp -d)
state_base="$base/state"
if [ -d /dev/shm ] && [ -w /dev/shm ]; then state_base=$(mktemp -d /dev/shm/homeworld-state.XXXXXX); fi
old_data=$HW_DATA; old_state=$HW_STATE; old_cache=$HW_CACHE
HW_DATA="$base/data"; HW_STATE="$state_base"; HW_CACHE="$base/cache"; export HW_DATA HW_STATE HW_CACHE
mkdir -p "$HW_DATA/generations" "$HW_STATE/locks" "$HW_CACHE"
module="$base/module"; mkdir -p "$module/config"; printf cross > "$module/config/file"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new); destination="$state_base/external"; hw_config_link config/file "$destination" mod "$gen"; hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
assert_eq "$(cat "$destination")" cross "cross-filesystem destination works"
assert_link "$destination" "$(hw_current)/config/mod/file" "temporary link is created beside destination"
HW_DATA=$old_data; HW_STATE=$old_state; HW_CACHE=$old_cache; export HW_DATA HW_STATE HW_CACHE
rm -rf "$base"; case "$state_base" in /dev/shm/*) rm -rf "$state_base" ;; esac

section "journal publication failure happens before pointer mutation"
setup_env
one=$(hw_gen_new); hw_gen_write_meta "$one" linux test '' one; hw_gen_activate "$one"
two=$(hw_gen_new); hw_gen_write_meta "$two" linux test '' two
old_current=$(readlink "$(hw_current)")
# A regular file where the journal directory must be makes begin fail.
rm -rf "$(hw_transaction_dir)"; mkdir -p "$(dirname "$(hw_transaction_dir)")"; printf blocked > "$(hw_transaction_dir)"
(hw_gen_activate "$two") >/dev/null 2>&1
assert_nonzero "$?" "unusable journal path fails activation"
assert_eq "$(readlink "$(hw_current)")" "$old_current" "current unchanged when journal cannot publish"
rm -f "$(hw_transaction_dir)"
teardown_env
