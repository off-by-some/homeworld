#!/bin/sh

section "asset add, link, and snapshot semantics"
setup_env
module="$_T_TMP/module"; mkdir -p "$module/tree/sub"
printf blob > "$module/blob"
printf visible > "$module/tree/sub/file"
printf hidden > "$module/tree/.hidden"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new)
hw_asset_add blob tool "$gen" mod
assert_file "$gen/assets/mod/tool" "asset staged"
hw_asset_add tree bundle "$gen" mod
printf changed > "$module/blob"
printf changed > "$module/tree/sub/file"
hw_asset_link tool "$_T_TMP/tool" "$gen" mod
hw_asset_link bundle "$_T_TMP/bundle" "$gen" mod
hw_gen_write_meta "$gen" linux test '' mod; hw_gen_activate "$gen"
assert_eq "$(cat "$_T_TMP/tool")" blob "file asset is a snapshot, not a live pointer"
assert_eq "$(cat "$_T_TMP/bundle/sub/file")" visible "directory asset snapshots nested files"
assert_eq "$(cat "$_T_TMP/bundle/.hidden")" hidden "directory asset snapshots dotfiles"
(ln -s blob "$module/link"; hw_asset_add link bad "$gen" mod) >/dev/null 2>&1
assert_nonzero "$?" "symlink asset source rejected"
teardown_env


section "directory asset publication precedes read-only freeze"
setup_env
module="$_T_TMP/module"; mkdir -p "$module/tree/sub"
printf payload > "$module/tree/sub/file"
HOMEWORLD_MODULE_ROOT="$module"; export HOMEWORLD_MODULE_ROOT
gen=$(hw_gen_new)
(hw_asset_add tree bundle "$gen" mod) >/dev/null 2>&1
assert_0 "$?" "directory asset publish succeeds"
assert_dir "$gen/assets/mod/bundle" "directory asset is published"
if [ -w "$gen/assets/mod/bundle" ]; then
    fail "published directory asset is read-only"
else
    ok "published directory asset is read-only"
fi
teardown_env


section "asset CLI is explicitly add then link"
setup_cli_env
source_dir="$_T_TMP/source"; make_module "$source_dir" root
mkdir -p "$source_dir/generated"
printf canonical > "$source_dir/generated/theme"
cat > "$source_dir/install.sh" <<EOF2
#!/bin/sh
homeworld asset add generated/theme theme
homeworld asset link theme "$_T_TMP/home/theme"
EOF2
chmod +x "$source_dir/install.sh"
hw_cli init "$source_dir" >/dev/null 2>&1
assert_0 "$?" "two-step asset CLI succeeds"
assert_eq "$(cat "$_T_TMP/home/theme")" canonical "two-step asset link exposes snapshot"
current_before=$(readlink "$(hw_data_dir)/current")
cat > "$source_dir/install.sh" <<EOF2
#!/bin/sh
homeworld asset link generated/theme theme "$_T_TMP/home/unexpected"
EOF2
chmod +x "$source_dir/install.sh"
hw_cli install --reinstall --yes >"$_T_TMP/out" 2>&1
assert_nonzero "$?" "asset link requires a named asset and destination"
assert_contains "$_T_TMP/out" 'usage: homeworld asset link <name> <destination>' "extra asset link argument reports canonical usage"
assert_eq "$(readlink "$(hw_data_dir)/current")" "$current_before" "rejected asset command preserves current generation"
assert_no_path "$_T_TMP/home/unexpected" "rejected asset command creates no destination"
teardown_cli_env
