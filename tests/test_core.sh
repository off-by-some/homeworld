#!/bin/sh
# test_core.sh — hw_safe_path, hw_version_ge, hw_require

section "hw_safe_path — valid inputs"

_r=$(hw_safe_path /base foo/bar)
assert_eq "$_r" "/base/foo/bar" "joins base and relative path"

_r=$(hw_safe_path /base file)
assert_eq "$_r" "/base/file" "single filename"

_r=$(hw_safe_path "/dir with spaces" "name with spaces")
assert_eq "$_r" "/dir with spaces/name with spaces" "handles spaces"

# A filename that *contains* two consecutive dots is NOT a traversal component —
# only the bare ".." segment (delimited by slashes or at the boundary) is unsafe.
_r=$(hw_safe_path /base "v1..2.cfg")
assert_eq "$_r" "/base/v1..2.cfg" "allows literal '..' inside a filename component"

_r=$(hw_safe_path /base "keep..dots/inside")
assert_eq "$_r" "/base/keep..dots/inside" "allows '..' embedded in directory name"

section "hw_safe_path — rejected inputs"

( hw_safe_path /base /absolute ) 2>/dev/null
assert_nonzero $? "rejects absolute path"

( hw_safe_path /base "../escape" ) 2>/dev/null
assert_nonzero $? "rejects leading .."

( hw_safe_path /base "foo/../bar" ) 2>/dev/null
assert_nonzero $? "rejects embedded .."

( hw_safe_path /base "a/b/../../etc/passwd" ) 2>/dev/null
assert_nonzero $? "rejects deep traversal (two steps up)"

# A component that *starts with* two dots but has more characters is fine
_r=$(hw_safe_path /base "..hidden")
assert_eq "$_r" "/base/..hidden" "allows filename starting with two dots"

section "hw_version_ge"

hw_version_ge "1.0.0" "1.0.0"; assert_0 $? "1.0.0 >= 1.0.0 (equal)"
hw_version_ge "2.0.0" "1.9.9"; assert_0 $? "2.0.0 >= 1.9.9 (major bump)"
hw_version_ge "1.1.0" "1.0.99"; assert_0 $? "1.1.0 >= 1.0.99 (minor bump)"
hw_version_ge "1.0.1" "1.0.0"; assert_0 $? "1.0.1 >= 1.0.0 (patch bump)"
hw_version_ge "1.0"   "1.0.0"; assert_0 $? "1.0 treated as 1.0.0"
hw_version_ge "10.0.0" "9.9.9"; assert_0 $? "10 > 9 numerically (not lexically)"

hw_version_ge "1.0.0" "1.0.1"; assert_nonzero $? "1.0.0 < 1.0.1"
hw_version_ge "0.9.9" "1.0.0"; assert_nonzero $? "0.9.9 < 1.0.0"
hw_version_ge "1.0.0" "2.0.0"; assert_nonzero $? "1.0.0 < 2.0.0"
hw_version_ge "1.9.9" "2.0.0"; assert_nonzero $? "1.9.9 < 2.0.0"

section "hw_require"

hw_require sh;  assert_0 $? "sh is present"
hw_require env; assert_0 $? "env is present"

( hw_require _no_such_command_xyz_abc_ ) 2>/dev/null
assert_nonzero $? "missing command fails"
