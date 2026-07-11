#!/bin/sh
# module.sh — module discovery, loading, filtering, sorting, and introspection.
#
# Modules are materialised as flat files in a scratch directory (moddir) so
# we never hold state in shell variables across function boundaries. Each
# field gets its own file: moddir/<name>/path, moddir/<name>/platforms, etc.
# This makes the representation simple and the individual field reads cheap.

# The seven recognised manifest fields. Anything else starting with HOMEWORLD_
# is rejected, which catches typos before they silently do nothing.
_HW_MODULE_KNOWN_FIELDS="HOMEWORLD_MODULE_NAME HOMEWORLD_DESCRIPTION HOMEWORLD_PLATFORMS HOMEWORLD_DISTROS HOMEWORLD_DEPENDS HOMEWORLD_AUTO_INSTALL HOMEWORLD_REQUIRES"

# hw_module_load manifest_path moddir
# Source the manifest in a subshell, validate, and write field files.
# The subshell isolation means a misbehaving manifest cannot contaminate our env.
hw_module_load() {
    _hml_manifest="$1"
    _hml_moddir="$2"
    _hml_dir=$(dirname "$_hml_manifest")

    # Run the manifest in a subshell and emit field=value lines we can parse.
    # All known HOMEWORLD_* vars are cleared first so stale values from a previous
    # module cannot leak through an omitted field.
    #
    # To detect unknown HOMEWORLD_* fields set by the manifest, we snapshot
    # the pre-source variable names, then diff against post-source names.
    # This avoids false positives from HOMEWORLD_* variables that already
    # exist in the environment (e.g. HOMEWORLD_COMMAND_DIR, HOMEWORLD_TARGET).
    _hml_output=$(
        # Snapshot any HOMEWORLD_* names that pre-exist in this subshell.
        # We'll exclude them from the unknown-field check.
        _pre_hw=$(set | grep '^HOMEWORLD_' | cut -d= -f1 | tr '\n' ' ')

        # Clear all seven known fields so a missing field from a previous
        # module doesn't persist.
        unset HOMEWORLD_MODULE_NAME HOMEWORLD_DESCRIPTION HOMEWORLD_PLATFORMS \
              HOMEWORLD_DISTROS HOMEWORLD_DEPENDS HOMEWORLD_AUTO_INSTALL \
              HOMEWORLD_REQUIRES 2>/dev/null || true

        # Source the manifest. Failure here exits the subshell; the parent
        # shell sees empty output and the caller detects the missing NAME.
        # shellcheck source=/dev/null
        . "$_hml_manifest" 2>/dev/null || exit 1

        # Emit each field so the parent shell can read it
        printf 'NAME=%s\n'         "${HOMEWORLD_MODULE_NAME:-}"
        printf 'DESCRIPTION=%s\n'  "${HOMEWORLD_DESCRIPTION:-}"
        printf 'PLATFORMS=%s\n'    "${HOMEWORLD_PLATFORMS:-}"
        printf 'DISTROS=%s\n'      "${HOMEWORLD_DISTROS:-}"
        printf 'DEPENDS=%s\n'      "${HOMEWORLD_DEPENDS:-}"
        printf 'AUTO_INSTALL=%s\n' "${HOMEWORLD_AUTO_INSTALL:-true}"
        printf 'REQUIRES=%s\n'     "${HOMEWORLD_REQUIRES:-}"

        # Report any HOMEWORLD_* vars that appeared after sourcing and were
        # not already present in the environment before sourcing.
        # Use a for loop (not pipe+while) to avoid parser issues in bash 3.2.
        # 'continue' is used as a non-empty command before ';;' because bash 3.2
        # rejects empty case arms (just ';;' with no preceding command).
        _post_hw=$(set | grep '^HOMEWORLD_' | cut -d= -f1 | tr '\n' ' ')
        for _env_key in $_post_hw; do
            case " $_HW_MODULE_KNOWN_FIELDS " in
                *" $_env_key "*)
                    continue
                    ;;
            esac
            case " $_pre_hw " in
                *" $_env_key "*)
                    continue
                    ;;
            esac
            printf 'UNKNOWN=%s\n' "$_env_key"
        done
    ) || {
        hw_die "could not load module manifest: $_hml_manifest" \
               "Ensure the file is valid POSIX sh and that HOMEWORLD_MODULE_NAME is set."
    }

    # Check for unknown fields first — better to fail early with a clear message
    _hml_unknown=$(printf '%s\n' "$_hml_output" | grep '^UNKNOWN=' | head -1)
    if [ -n "$_hml_unknown" ]; then
        _hml_field="${_hml_unknown#UNKNOWN=}"
        hw_die "unknown manifest field '$_hml_field' in $_hml_manifest" \
               "Valid fields: HOMEWORLD_MODULE_NAME, DESCRIPTION, PLATFORMS, DISTROS, DEPENDS, AUTO_INSTALL, REQUIRES."
    fi

    # Extract name and validate against required pattern
    _hml_name=$(printf '%s\n' "$_hml_output" | grep '^NAME=' | head -1)
    _hml_name="${_hml_name#NAME=}"

    if [ -z "$_hml_name" ]; then
        hw_die "HOMEWORLD_MODULE_NAME is not set in $_hml_manifest" \
               "Add a line like: HOMEWORLD_MODULE_NAME=\"your-module-name\""
    fi

    # Validate: must match [a-z0-9][a-z0-9._-]*. Strip valid chars and check
    # what's left; if anything remains the name contains illegal characters.
    _hml_name_bad=$(printf '%s' "$_hml_name" | tr -d 'a-z0-9._-')
    _hml_first_bad=$(printf '%s' "$_hml_name" | cut -c1 | tr -d 'a-z0-9')
    if [ -n "$_hml_name_bad" ] || [ -n "$_hml_first_bad" ]; then
        hw_die "invalid module name: '$_hml_name'" \
               "Names must match [a-z0-9][a-z0-9._-]* — start with a letter or digit, then letters, digits, dots, hyphens, or underscores only."
    fi

    # Create the module's directory in moddir and write field files
    _hml_dest="$_hml_moddir/$_hml_name"
    mkdir -p "$_hml_dest"

    # Write each field — using printf to a file is safe even for values with newlines
    _hml_desc=$(printf '%s\n' "$_hml_output" | grep '^DESCRIPTION=' | head -1)
    _hml_desc="${_hml_desc#DESCRIPTION=}"
    _hml_plat=$(printf '%s\n' "$_hml_output" | grep '^PLATFORMS=' | head -1)
    _hml_plat="${_hml_plat#PLATFORMS=}"
    _hml_dist=$(printf '%s\n' "$_hml_output" | grep '^DISTROS=' | head -1)
    _hml_dist="${_hml_dist#DISTROS=}"
    _hml_deps=$(printf '%s\n' "$_hml_output" | grep '^DEPENDS=' | head -1)
    _hml_deps="${_hml_deps#DEPENDS=}"
    _hml_auto=$(printf '%s\n' "$_hml_output" | grep '^AUTO_INSTALL=' | head -1)
    _hml_auto="${_hml_auto#AUTO_INSTALL=}"
    _hml_req=$(printf '%s\n' "$_hml_output" | grep '^REQUIRES=' | head -1)
    _hml_req="${_hml_req#REQUIRES=}"

    printf '%s' "$_hml_dir"   > "$_hml_dest/path"
    printf '%s' "$_hml_plat"  > "$_hml_dest/platforms"
    printf '%s' "$_hml_dist"  > "$_hml_dest/distros"
    printf '%s' "$_hml_deps"  > "$_hml_dest/depends"
    printf '%s' "${_hml_auto:-true}" > "$_hml_dest/auto_install"
    printf '%s' "$_hml_desc"  > "$_hml_dest/description"
    printf '%s' "$_hml_req"   > "$_hml_dest/requires"

    printf '%s\n' "$_hml_name"
}

# hw_module_discover source_dir moddir
# Walk source_dir for .homeworld-module files, load each, return newline-
# separated module names. The root manifest must exist.
hw_module_discover() {
    _hmd_source="$1"
    _hmd_moddir="$2"

    # The root sentinel is mandatory — without it we'd silently provision
    # an unrelated directory.
    if [ ! -f "$_hmd_source/.homeworld-module" ]; then
        hw_die "no .homeworld-module found at source root: $_hmd_source" \
               "Create a .homeworld-module manifest at the root of your provisioning source directory."
    fi

    # find emits paths; we process them one at a time using a while loop.
    # Because the loop runs in a pipe subshell, hw_die (exit 1) cannot
    # propagate fatally to the caller — we use a sentinel file instead.
    _hmd_tmp=$(mktemp)
    _hmd_err=$(mktemp)

    find "$_hmd_source" -name '.homeworld-module' -type f | sort | while read -r _hmd_manifest; do
        # Redirect hw_die errors to the sentinel so the caller can re-die
        if ! _hmd_name=$(hw_module_load "$_hmd_manifest" "$_hmd_moddir" 2>"$_hmd_err"); then
            # hw_die already printed the message via stderr in the subshell;
            # write the message to the sentinel so the outer context can die too
            cat "$_hmd_err" >&2
            # Signal fatal error to the parent via a flag file
            printf 'error\n' > "${_hmd_tmp}.fatal"
            break
        fi
        printf '%s\n' "$_hmd_name" >> "$_hmd_tmp"
    done

    # Re-raise any fatal error that occurred inside the pipe subshell
    if [ -f "${_hmd_tmp}.fatal" ]; then
        rm -f "$_hmd_tmp" "${_hmd_tmp}.fatal" "$_hmd_err"
        # The error message was already printed; just exit
        exit 1
    fi

    cat "$_hmd_tmp"
    rm -f "$_hmd_tmp" "${_hmd_tmp}.fatal" "$_hmd_err"
}

# hw_module_get moddir name field
# Read a single field from the module store. Returns empty string if missing.
hw_module_get() {
    _hmg_moddir="$1"
    _hmg_name="$2"
    _hmg_field="$3"
    _hmg_file="$_hmg_moddir/$_hmg_name/$_hmg_field"
    if [ -f "$_hmg_file" ]; then
        cat "$_hmg_file"
    fi
    # Empty output for missing files is intentional and documented
}

# hw_module_applicable moddir name platform distro
# Returns 0 if the module should be installed. Returns 1 and prints the
# reason to stdout if it should be skipped — the caller decides visibility.
hw_module_applicable() {
    _hma_moddir="$1"
    _hma_name="$2"
    _hma_platform="$3"
    _hma_distro="$4"

    _hma_platforms=$(hw_module_get "$_hma_moddir" "$_hma_name" "platforms")
    _hma_distros=$(hw_module_get "$_hma_moddir" "$_hma_name" "distros")

    # Empty platforms means "all platforms" — no check needed
    if [ -n "$_hma_platforms" ]; then
        _hma_match=0
        for _hma_p in $_hma_platforms; do
            [ "$_hma_p" = "$_hma_platform" ] && { _hma_match=1; break; }
        done
        if [ "$_hma_match" = "0" ]; then
            printf 'unsupported on %s' "$_hma_platform"
            return 1
        fi
    fi

    # Empty distros means "all distros" — only check if both fields are set.
    # If the distro is unknown (empty) and a distro list is specified, we skip.
    if [ -n "$_hma_distros" ]; then
        if [ -z "$_hma_distro" ]; then
            printf 'distro list set but current distro is unknown'
            return 1
        fi
        _hma_dmatch=0
        for _hma_d in $_hma_distros; do
            [ "$_hma_d" = "$_hma_distro" ] && { _hma_dmatch=1; break; }
        done
        if [ "$_hma_dmatch" = "0" ]; then
            printf 'not applicable for distro %s' "$_hma_distro"
            return 1
        fi
    fi

    return 0
}

# hw_module_sort moddir names
# Topological sort via repeated-pass algorithm. Space-separated input and output.
# Dies with a useful message after 100 passes without progress (cycle detected).
hw_module_sort() {
    _hms_moddir="$1"
    _hms_names="$2"

    _hms_pending="$_hms_names"
    _hms_emitted=""
    _hms_pass=0

    while [ -n "$_hms_pending" ]; do
        _hms_pass=$(expr "$_hms_pass" + 1)
        if [ "$_hms_pass" -gt 100 ]; then
            hw_die "dependency cycle detected among modules: $_hms_pending" \
                   "Check HOMEWORLD_DEPENDS in each module's manifest for circular references."
        fi

        _hms_progress=0
        _hms_next=""

        for _hms_name in $_hms_pending; do
            _hms_deps=$(hw_module_get "$_hms_moddir" "$_hms_name" "depends")
            _hms_deps_ok=1

            # Check that every declared dependency has already been emitted
            for _hms_dep in $_hms_deps; do
                _hms_found=0
                for _hms_e in $_hms_emitted; do
                    [ "$_hms_e" = "$_hms_dep" ] && { _hms_found=1; break; }
                done
                if [ "$_hms_found" = "0" ]; then
                    # Dependency not yet emitted — check if it's even in our set
                    _hms_in_set=0
                    for _hms_p in $_hms_pending; do
                        [ "$_hms_p" = "$_hms_dep" ] && { _hms_in_set=1; break; }
                    done
                    if [ "$_hms_in_set" = "0" ]; then
                        hw_die "module '$_hms_name' depends on '$_hms_dep', which is not in the install plan" \
                               "Add '$_hms_dep' to the plan or remove it from HOMEWORLD_DEPENDS in '$_hms_name'."
                    fi
                    _hms_deps_ok=0
                    break
                fi
            done

            if [ "$_hms_deps_ok" = "1" ]; then
                _hms_emitted="$_hms_emitted $_hms_name"
                _hms_progress=1
            else
                # Keep it in the pending set
                _hms_next="$_hms_next $_hms_name"
            fi
        done

        if [ "$_hms_progress" = "0" ] && [ -n "$_hms_next" ]; then
            hw_die "dependency cycle detected among modules: $_hms_next" \
                   "Check HOMEWORLD_DEPENDS in each module's manifest for circular references."
        fi

        _hms_pending="$_hms_next"
    done

    # Strip leading space
    printf '%s' "${_hms_emitted# }"
}

# hw_module_check_commands moddir names
# Verify that no command name is provided by more than one module.
# Collision detection happens before any install work begins.
hw_module_check_commands() {
    _hmcc_moddir="$1"
    _hmcc_names="$2"

    # Build a list of "command:module" pairs, then look for duplicate command names
    _hmcc_seen=""

    for _hmcc_name in $_hmcc_names; do
        _hmcc_path=$(hw_module_get "$_hmcc_moddir" "$_hmcc_name" "path")
        _hmcc_cmd_dir="$_hmcc_path/commands"
        [ -d "$_hmcc_cmd_dir" ] || continue

        for _hmcc_cmd in "$_hmcc_cmd_dir"/*/; do
            [ -d "$_hmcc_cmd" ] || continue
            _hmcc_cmd_name=$(basename "$_hmcc_cmd")

            # Check if we've already seen this command name
            for _hmcc_entry in $_hmcc_seen; do
                _hmcc_entry_cmd="${_hmcc_entry%%:*}"
                _hmcc_entry_mod="${_hmcc_entry#*:}"
                if [ "$_hmcc_entry_cmd" = "$_hmcc_cmd_name" ]; then
                    hw_die "command name conflict: '$_hmcc_cmd_name' is provided by both '$_hmcc_entry_mod' and '$_hmcc_name'" \
                           "Command names must be unique across all modules — rename one of the commands."
                fi
            done

            _hmcc_seen="$_hmcc_seen ${_hmcc_cmd_name}:${_hmcc_name}"
        done
    done
}

# hw_module_collect_packages moddir name provider
# Print package names from packages/<provider>.txt, one per line.
# Blank lines and comments are filtered. Empty output if the file doesn't exist.
hw_module_collect_packages() {
    _hmcp_moddir="$1"
    _hmcp_name="$2"
    _hmcp_provider="$3"

    _hmcp_path=$(hw_module_get "$_hmcp_moddir" "$_hmcp_name" "path")
    _hmcp_pkg_file="$_hmcp_path/packages/${_hmcp_provider}.txt"

    [ -f "$_hmcp_pkg_file" ] || return 0

    grep -v '^[[:space:]]*$' "$_hmcp_pkg_file" | grep -v '^[[:space:]]*#' || true
}
