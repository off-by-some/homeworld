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
