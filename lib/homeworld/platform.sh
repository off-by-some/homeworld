#!/bin/sh
# platform.sh — OS and package provider detection
# All functions are pure (no state changes) and can be called multiple times.

# hw_detect_platform — normalise uname output to our two supported values.
hw_detect_platform() {
    _plat=$(uname -s 2>/dev/null) || _plat=""
    case "$_plat" in
        Linux)  printf 'linux'  ;;
        Darwin) printf 'macos'  ;;
        *)      printf 'linux'  ;; # best-effort fallback
    esac
}

# hw_detect_distro — read the ID field from /etc/os-release.
# Returns empty string on macOS or any system without the file.
hw_detect_distro() {
    if [ -r /etc/os-release ]; then
        # The file uses shell-assignment syntax, so we can grep without sourcing.
        _id=$(grep '^ID=' /etc/os-release 2>/dev/null | head -1)
        _id="${_id#ID=}"
        # Strip surrounding quotes if present
        _id="${_id%\"}"
        _id="${_id#\"}"
        _id="${_id%\'}"
        _id="${_id#\'}"
        printf '%s' "$_id"
    fi
    # Empty output is the documented signal for "no distro info"
}

# hw_detect_provider — infer the package manager from what's actually installed.
# Accepts the platform name so we can weight the check sensibly.
hw_detect_provider() {
    _prov_platform="$1"
    case "$_prov_platform" in
        macos)
            command -v brew >/dev/null 2>&1 && { printf 'brew'; return 0; }
            ;;
        *)
            # Check in preference order; most specific distros own exactly one.
            command -v pacman  >/dev/null 2>&1 && { printf 'pacman'; return 0; }
            command -v apt-get >/dev/null 2>&1 && { printf 'apt';    return 0; }
            command -v dnf     >/dev/null 2>&1 && { printf 'dnf';    return 0; }
            command -v brew    >/dev/null 2>&1 && { printf 'brew';   return 0; }
            ;;
    esac
    # Empty output means no recognised provider — the caller decides whether
    # that's fatal (modules with package requirements) or acceptable (no packages).
}

# hw_version_ge v1 v2 — true if v1 >= v2.
# Parses MAJOR.MINOR[.PATCH] by splitting on '.' and comparing numerically.
# Using expr so we stay POSIX-clean without arithmetic builtins.
hw_version_ge() {
    _vge_v1="$1"
    _vge_v2="$2"

    # Pull apart each component; default missing patch to 0
    _vge_maj1="${_vge_v1%%.*}"
    _vge_rest1="${_vge_v1#*.}"
    _vge_min1="${_vge_rest1%%.*}"
    _vge_pat1="${_vge_rest1#*.}"
    # If there was no second dot, pat equals min — treat as 0
    [ "$_vge_pat1" = "$_vge_min1" ] && _vge_pat1="0"

    _vge_maj2="${_vge_v2%%.*}"
    _vge_rest2="${_vge_v2#*.}"
    _vge_min2="${_vge_rest2%%.*}"
    _vge_pat2="${_vge_rest2#*.}"
    [ "$_vge_pat2" = "$_vge_min2" ] && _vge_pat2="0"

    # Ensure all components are numeric before feeding to expr
    _vge_maj1=$(printf '%d' "${_vge_maj1:-0}" 2>/dev/null) || _vge_maj1=0
    _vge_min1=$(printf '%d' "${_vge_min1:-0}" 2>/dev/null) || _vge_min1=0
    _vge_pat1=$(printf '%d' "${_vge_pat1:-0}" 2>/dev/null) || _vge_pat1=0
    _vge_maj2=$(printf '%d' "${_vge_maj2:-0}" 2>/dev/null) || _vge_maj2=0
    _vge_min2=$(printf '%d' "${_vge_min2:-0}" 2>/dev/null) || _vge_min2=0
    _vge_pat2=$(printf '%d' "${_vge_pat2:-0}" 2>/dev/null) || _vge_pat2=0

    # Compare lexicographically encoded as a single tuple
    if expr "$_vge_maj1" \> "$_vge_maj2" >/dev/null 2>&1; then return 0; fi
    if expr "$_vge_maj1" \< "$_vge_maj2" >/dev/null 2>&1; then return 1; fi
    if expr "$_vge_min1" \> "$_vge_min2" >/dev/null 2>&1; then return 0; fi
    if expr "$_vge_min1" \< "$_vge_min2" >/dev/null 2>&1; then return 1; fi
    if expr "$_vge_pat1" \> "$_vge_pat2" >/dev/null 2>&1; then return 0; fi
    if expr "$_vge_pat1" \< "$_vge_pat2" >/dev/null 2>&1; then return 1; fi
    return 0  # equal
}
