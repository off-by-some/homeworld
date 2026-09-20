#!/bin/sh

section "end-to-end install, repository update, and rollback"
setup_cli_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
source_dir="$_T_TMP/source"; make_module "$source_dir" root
mkdir -p "$source_dir/config"; printf first > "$source_dir/config/value"
cat > "$source_dir/install.sh" <<EOF2
#!/bin/sh
homeworld config add config/value value
homeworld config link value "$_T_TMP/home/config-link"
homeworld repo add "$repo" tools --ref "$branch"
homeworld repo link tools "$_T_TMP/home/tools"
EOF2
chmod +x "$source_dir/install.sh"
hw_cli init "$source_dir" >/dev/null 2>&1
assert_0 "$?" "initial install succeeds"
assert_eq "$(cat "$_T_TMP/home/config-link")" first "config active"
assert_eq "$(cat "$_T_TMP/home/tools/file.txt")" one "repository active"
old=$(readlink "$(hw_data_dir)/current")
git_commit "$repo" file.txt two
hw_cli repo update tools >/dev/null 2>&1
assert_eq "$(cat "$_T_TMP/home/tools/file.txt")" one "repo update alone does not activate"
printf second > "$source_dir/config/value"
hw_cli install >/dev/null 2>&1
assert_0 "$?" "second install succeeds"
assert_eq "$(cat "$_T_TMP/home/config-link")" second "new config active"
assert_eq "$(cat "$_T_TMP/home/tools/file.txt")" two "new repo commit active"
hw_cli generation rollback >/dev/null 2>&1
assert_eq "$(cat "$_T_TMP/home/config-link")" first "rollback restores config"
assert_eq "$(cat "$_T_TMP/home/tools/file.txt")" one "rollback restores repository commit"
assert_dir "$old" "old generation retained"
teardown_cli_env

section "safe reinstall failure"
setup_cli_env
source_dir="$_T_TMP/source"; make_module "$source_dir" root
mkdir -p "$source_dir/config"; printf good > "$source_dir/config/value"
cat > "$source_dir/install.sh" <<EOF2
#!/bin/sh
homeworld config add config/value value
homeworld config link value "$_T_TMP/home/value"
EOF2
chmod +x "$source_dir/install.sh"
hw_cli init "$source_dir" >/dev/null 2>&1
current_before=$(readlink "$(hw_data_dir)/current")
printf '%s\n' '#!/bin/sh' 'exit 1' > "$source_dir/install.sh"; chmod +x "$source_dir/install.sh"
hw_cli install --reinstall --yes >/dev/null 2>&1
assert_nonzero "$?" "failed reinstall reports failure"
assert_eq "$(readlink "$(hw_data_dir)/current")" "$current_before" "failed reinstall preserves current"
assert_eq "$(cat "$_T_TMP/home/value")" good "failed reinstall preserves binding"
teardown_cli_env

section "deprecated commands provide guidance"
setup_cli_env
hw_cli rollback >"$_T_TMP/out" 2>&1
assert_nonzero "$?" "old rollback fails"
assert_contains "$_T_TMP/out" 'homeworld generation rollback' "rename guidance"
teardown_cli_env

section "module version cache skips install.sh when unchanged"
setup_cli_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
counter="$_T_TMP/run-count"; : > "$counter"
source_dir="$_T_TMP/source"
make_module "$source_dir" root 'HOMEWORLD_MODULE_VERSION="1.0.0"'
mkdir -p "$source_dir/config"; printf first > "$source_dir/config/value"
make_command "$source_dir" greet
cat > "$source_dir/install.sh" <<EOF2
#!/bin/sh
printf run >> "$counter"
homeworld config add config/value value
homeworld config link value "$_T_TMP/home/config-link"
homeworld repo add "$repo" tools --ref "$branch"
homeworld repo link tools "$_T_TMP/home/tools"
EOF2
chmod +x "$source_dir/install.sh"
hw_cli init "$source_dir" >/dev/null 2>&1
assert_0 "$?" "initial install succeeds"
assert_eq "$(wc -c < "$counter" | tr -d ' ')" "3" "install.sh ran once"
assert_eq "$(cat "$_T_TMP/home/config-link")" first "config active"
assert_eq "$(cat "$_T_TMP/home/tools/file.txt")" one "repository active"

# Change on-disk content but keep the declared version the same, and move the
# upstream branch forward. A pure disk-hash cache would either miss the config
# change or (worse) silently stop tracking the branch; the version-gated cache
# is expected to skip entirely and keep serving exactly what was recorded.
printf second > "$source_dir/config/value"
git_commit "$repo" file.txt two
hw_cli install >/dev/null 2>&1
assert_0 "$?" "second install succeeds"
assert_eq "$(wc -c < "$counter" | tr -d ' ')" "3" "install.sh did not run again"
assert_eq "$(cat "$_T_TMP/home/config-link")" first "carried-forward config still active"
assert_eq "$(cat "$_T_TMP/home/tools/file.txt")" one "carried-forward repo commit still active"
assert_eq "$("$(hw_data_dir)/current/bin/greet")" greet "carried-forward command launcher still works"

# --reinstall bypasses the cache unconditionally.
hw_cli install --reinstall --yes >/dev/null 2>&1
assert_0 "$?" "reinstall succeeds"
assert_eq "$(wc -c < "$counter" | tr -d ' ')" "6" "install.sh ran again under --reinstall"
assert_eq "$(cat "$_T_TMP/home/config-link")" second "reinstall picks up new config"
assert_eq "$(cat "$_T_TMP/home/tools/file.txt")" two "reinstall picks up new repo commit"

# Bumping the declared version re-enables the module normally, no flag needed.
make_module "$source_dir" root 'HOMEWORLD_MODULE_VERSION="2.0.0"'
hw_cli install >/dev/null 2>&1
assert_0 "$?" "version bump install succeeds"
assert_eq "$(wc -c < "$counter" | tr -d ' ')" "9" "install.sh ran again after version bump"
teardown_cli_env

section "repository links compose nested named state"
setup_cli_env
repo="$_T_TMP/repo"; make_git_repo "$repo" one; branch=$(git -C "$repo" symbolic-ref --short HEAD)
versions="$_T_TMP/persistent versions"; mkdir -p "$versions"; printf persistent > "$versions/marker"
hw_cli state bind pyenv-versions "$versions" >/dev/null 2>&1
source_dir="$_T_TMP/source"; make_module "$source_dir" root
cat > "$source_dir/install.sh" <<EOF2
#!/bin/sh
homeworld repo add "$repo" pyenv --ref "$branch"
homeworld repo link pyenv "$_T_TMP/home/.pyenv"
homeworld state link pyenv-versions "$_T_TMP/home/.pyenv/versions"
EOF2
chmod +x "$source_dir/install.sh"
hw_cli init "$source_dir" >/dev/null 2>&1
assert_0 "$?" "nested state install succeeds"
assert_eq "$(cat "$_T_TMP/home/.pyenv/file.txt")" one "repository content remains visible"
assert_eq "$(cat "$_T_TMP/home/.pyenv/versions/marker")" persistent "nested persistent state is visible"
checkout=$(cd "$(hw_data_dir)/current/repos/pyenv" && pwd -P)
assert_no_path "$checkout/versions" "install does not modify immutable checkout"
teardown_cli_env

section "failed package installation stops the install"
setup_cli_env
# Fake sudo/pacman on PATH ahead of anything real, so this is hermetic across
# every platform the suite runs on (some have apt/dnf/brew instead, or no
# package manager at all in a bare container). The fake pacman always fails,
# simulating a bad sudo password or an interrupted package install.
fakebin="$_T_TMP/fakebin"; mkdir -p "$fakebin"
printf '#!/bin/sh\nexec "$@"\n' > "$fakebin/sudo"; chmod +x "$fakebin/sudo"
printf '#!/bin/sh\nprintf "pacman: simulated failure\\n" >&2\nexit 1\n' > "$fakebin/pacman"
chmod +x "$fakebin/pacman"
source_dir="$_T_TMP/source"; make_module "$source_dir" root
mkdir -p "$source_dir/packages"; printf 'some-package\n' > "$source_dir/packages/pacman.txt"
marker="$_T_TMP/install-ran"
cat > "$source_dir/install.sh" <<EOF2
#!/bin/sh
: > "$marker"
EOF2
chmod +x "$source_dir/install.sh"
PATH="$fakebin:$PATH" hw_cli init "$source_dir" >"$_T_TMP/out" 2>&1
assert_nonzero "$?" "install fails when package installation fails"
assert_contains "$_T_TMP/out" "package installation failed" "reports the right error"
assert_no_path "$marker" "module install.sh never ran"
assert_no_path "$(hw_data_dir)/current" "no generation activated"
teardown_cli_env
