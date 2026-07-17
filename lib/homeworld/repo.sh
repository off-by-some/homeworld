#!/bin/sh
# repo.sh — commit-pinned Git resources backed by mutable mirrors.
#
# Mirrors are disposable caches. A generation references a regular local clone
# detached at an exact commit. --no-hardlinks keeps checkout permissions and
# object lifetimes independent from the mutable mirror.

hw_repo_reject_secret_source() {
    _hrrs_source=$1
    hw_reject_line_breaks "$_hrrs_source" "repository source"
    case "$_hrrs_source" in
        *\?* | *\#*) hw_die "repository URLs with query strings or fragments are not supported" ;;
    esac
    case "$_hrrs_source" in
        http://* | https://*)
            _hrrs_authority=${_hrrs_source#*://}
            _hrrs_authority=${_hrrs_authority%%/*}
            case "$_hrrs_authority" in *@*) hw_die "repository URLs with embedded credentials are not supported" ;; esac
            ;;
        ssh://*)
            _hrrs_authority=${_hrrs_source#ssh://}
            _hrrs_authority=${_hrrs_authority%%/*}
            case "$_hrrs_authority" in *:*@*) hw_die "repository URLs with embedded passwords are not supported" ;; esac
            ;;
    esac
}

hw_repo_canonical_source() {
    _hrcs_source=$1
    hw_repo_reject_secret_source "$_hrcs_source"
    case "$_hrcs_source" in
        file://*) _hrcs_source=${_hrcs_source#file://} ;;
    esac
    case "$_hrcs_source" in
        http://* | https://* | ssh://* | git@*) printf '%s' "$_hrcs_source"; return 0 ;;
        \~/*) _hrcs_source="$HOME/${_hrcs_source#\~/}" ;;
    esac
    case "$_hrcs_source" in
        *)
            [ -d "$_hrcs_source" ] || hw_die "repository path does not exist"
            _hrcs_dir=$(cd -P "$_hrcs_source" 2>/dev/null && pwd) || hw_die "cannot resolve repository path"
            git -C "$_hrcs_dir" rev-parse --git-dir >/dev/null 2>&1 \
                || hw_die "local repository source is not a Git repository"
            _hrcs_bare=$(git -C "$_hrcs_dir" rev-parse --is-bare-repository 2>/dev/null || printf false)
            if [ "$_hrcs_bare" != true ]; then
                _hrcs_dirty=$(git -C "$_hrcs_dir" status --porcelain 2>/dev/null)
                [ -z "$_hrcs_dirty" ] || hw_die "local repository has uncommitted changes"
            fi
            printf '%s' "$_hrcs_dir"
            ;;
    esac
}

hw_repo_source_id() {
    _hrsi_source=$1
    if command -v git >/dev/null 2>&1; then
        printf '%s' "$_hrsi_source" | git hash-object --stdin
    else
        printf '%s' "$_hrsi_source" | cksum | awk '{print $1}'
    fi
}

hw_repo_mirror_path() { printf '%s/%s.git' "$(hw_mirrors_dir)" "$1"; }
hw_repo_checkout_path() { printf '%s/%s/%s' "$(hw_checkouts_dir)" "$1" "$2"; }
hw_repo_source_lock() { printf '%s/locks/repo-%s.lock' "$HW_STATE" "$1"; }

hw_repo_is_remote() {
    case "$1" in http://* | https://* | ssh://* | git@*) return 0 ;; *) return 1 ;; esac
}

hw_repo_mirror_ensure_locked() {
    _hrme_source=$1
    _hrme_id=$2
    _hrme_mirror=$(hw_repo_mirror_path "$_hrme_id")
    [ -d "$_hrme_mirror" ] && git --git-dir="$_hrme_mirror" rev-parse --is-bare-repository >/dev/null 2>&1 && return 0

    _hrme_tmp="${_hrme_mirror}.tmp-$$"
    _hrme_bad="${_hrme_mirror}.bad-$$"
    rm -rf "$_hrme_tmp" "$_hrme_bad"
    [ ! -e "$_hrme_mirror" ] || mv "$_hrme_mirror" "$_hrme_bad"
    git clone --mirror "$_hrme_source" "$_hrme_tmp" >/dev/null 2>&1 || {
        rm -rf "$_hrme_tmp"
        [ ! -e "$_hrme_bad" ] || mv "$_hrme_bad" "$_hrme_mirror"
        return 1
    }
    mv "$_hrme_tmp" "$_hrme_mirror" || {
        rm -rf "$_hrme_tmp"
        [ ! -e "$_hrme_bad" ] || mv "$_hrme_bad" "$_hrme_mirror"
        return 1
    }
    rm -rf "$_hrme_bad"
}

hw_repo_fetch_locked() {
    _hrfl_source=$1
    _hrfl_id=$2
    _hrfl_mirror=$(hw_repo_mirror_path "$_hrfl_id")
    hw_repo_mirror_ensure_locked "$_hrfl_source" "$_hrfl_id" || return 1
    # shellcheck disable=SC2086
    if git --git-dir="$_hrfl_mirror" fetch --prune ${GIT_FETCH_OPTIONS:-} origin \
        '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' >/dev/null 2>&1; then
        return 0
    fi

    # A healthy mirror is retained on network or authentication failure. A
    # corrupt mirror is quarantined and rebuilt once without touching any
    # existing immutable checkout.
    if git --git-dir="$_hrfl_mirror" fsck --no-dangling >/dev/null 2>&1; then
        return 1
    fi
    _hrfl_quarantine="${_hrfl_mirror}.corrupt-$(date +%s 2>/dev/null || printf '%s' $$)"
    mv "$_hrfl_mirror" "$_hrfl_quarantine" || return 1
    if hw_repo_mirror_ensure_locked "$_hrfl_source" "$_hrfl_id" && \
       git --git-dir="$_hrfl_mirror" fetch --prune ${GIT_FETCH_OPTIONS:-} origin \
        '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' >/dev/null 2>&1; then
        rm -rf "$_hrfl_quarantine"
        return 0
    fi
    rm -rf "$_hrfl_mirror"
    mv "$_hrfl_quarantine" "$_hrfl_mirror" 2>/dev/null || true
    return 1
}

hw_repo_fetch_source() {
    _hrfs_source=$1
    _hrfs_id=$2
    _hrfs_lock=$(hw_repo_source_lock "$_hrfs_id")
    hw_lock_acquire "$_hrfs_lock" "repository source"
    if ! hw_repo_fetch_locked "$_hrfs_source" "$_hrfs_id"; then
        hw_lock_release "$_hrfs_lock"
        return 1
    fi
    hw_lock_release "$_hrfs_lock"
}

# Parse the symbolic HEAD line produced by `git ls-remote --symref`.
# Git separates fields with tabs, but awk intentionally accepts any shell-style
# whitespace so the parser also tolerates compatible Git implementations.
hw_repo_parse_remote_head() {
    awk '
        $1 == "ref:" && $2 ~ /^refs\/heads\// && $3 == "HEAD" {
            print $2
            found = 1
            exit
        }
        END {
            if (!found)
                exit 1
        }
    '
}

hw_repo_default_ref() {
    _hrdr_source=$1
    if hw_repo_is_remote "$_hrdr_source"; then
        _hrdr_ref=$(
            git ls-remote --symref "$_hrdr_source" HEAD 2>/dev/null \
                | hw_repo_parse_remote_head
        ) || return 1
        [ -n "$_hrdr_ref" ] || return 1
        printf '%s' "$_hrdr_ref"
    else
        _hrdr_ref=$(git -C "$_hrdr_source" symbolic-ref -q HEAD 2>/dev/null) || return 1
        printf '%s' "$_hrdr_ref"
    fi
}

hw_repo_validate_ref() {
    _hrvr_ref=$1
    hw_reject_line_breaks "$_hrvr_ref" "repository ref"
    case "$_hrvr_ref" in '' | -* | *'@{'*) hw_die "invalid repository ref" ;; esac
    git check-ref-format --branch "$_hrvr_ref" >/dev/null 2>&1 && return 0
    case "$_hrvr_ref" in
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*) return 0 ;;
    esac
    hw_die "invalid repository ref"
}

hw_repo_resolve_locked() {
    _hrrl_id=$1
    _hrrl_ref=$2
    _hrrl_mirror=$(hw_repo_mirror_path "$_hrrl_id")
    hw_repo_validate_ref "$_hrrl_ref"

    # Prefer a full ref. For short names, reject branch/tag ambiguity.
    case "$_hrrl_ref" in
        refs/*) _hrrl_candidate="$_hrrl_ref" ;;
        *)
            _hrrl_branch="refs/heads/$_hrrl_ref"
            _hrrl_tag="refs/tags/$_hrrl_ref"
            _hrrl_has_branch=0; _hrrl_has_tag=0
            git --git-dir="$_hrrl_mirror" show-ref --verify --quiet "$_hrrl_branch" && _hrrl_has_branch=1
            git --git-dir="$_hrrl_mirror" show-ref --verify --quiet "$_hrrl_tag" && _hrrl_has_tag=1
            if [ "$_hrrl_has_branch" = 1 ] && [ "$_hrrl_has_tag" = 1 ]; then
                hw_die "repository ref is ambiguous between a branch and tag: $_hrrl_ref"
            elif [ "$_hrrl_has_branch" = 1 ]; then
                _hrrl_candidate="$_hrrl_branch"
            elif [ "$_hrrl_has_tag" = 1 ]; then
                _hrrl_candidate="$_hrrl_tag"
            else
                _hrrl_candidate="$_hrrl_ref"
            fi
            ;;
    esac
    _hrrl_sha=$(git --git-dir="$_hrrl_mirror" rev-parse --verify "${_hrrl_candidate}^{commit}" 2>/dev/null) || return 1
    hw_reject_line_breaks "$_hrrl_sha" "resolved commit"
    [ "${#_hrrl_sha}" -ge 40 ] || return 1
    printf '%s' "$_hrrl_sha"
}

hw_repo_checkout_locked() {
    _hrcl_id=$1
    _hrcl_sha=$2
    _hrcl_mirror=$(hw_repo_mirror_path "$_hrcl_id")
    _hrcl_final=$(hw_repo_checkout_path "$_hrcl_id" "$_hrcl_sha")
    [ -d "$_hrcl_final" ] && { printf '%s' "$_hrcl_final"; return 0; }
    mkdir -p "$(dirname "$_hrcl_final")"
    _hrcl_tmp="${_hrcl_final}.tmp-$$"
    rm -rf "$_hrcl_tmp"
    git clone --local --no-hardlinks --no-checkout "$_hrcl_mirror" "$_hrcl_tmp" >/dev/null 2>&1 || { rm -rf "$_hrcl_tmp"; return 1; }
    git -C "$_hrcl_tmp" checkout --detach "$_hrcl_sha" >/dev/null 2>&1 || { rm -rf "$_hrcl_tmp"; return 1; }
    mv "$_hrcl_tmp" "$_hrcl_final" || { rm -rf "$_hrcl_tmp"; return 1; }
    chmod -R a-w "$_hrcl_final" 2>/dev/null || true
    printf '%s' "$_hrcl_final"
}

hw_repo_manifest_dir() { printf '%s/.homeworld/repo-manifest' "$1"; }

hw_repo_record() {
    _hrr_ns=$1; _hrr_source=$2; _hrr_id=$3; _hrr_mode=$4; _hrr_ref=$5; _hrr_sha=$6; _hrr_gen=$7
    _hrr_root=$(hw_repo_manifest_dir "$_hrr_gen")
    mkdir -p "$_hrr_root"
    [ -f "$_hrr_root/schema-version" ] || hw_schema_write "$_hrr_root"
    _hrr_dir="$_hrr_root/$_hrr_ns"
    _hrr_tmp="${_hrr_dir}.tmp-$$"
    rm -rf "$_hrr_tmp"
    mkdir -p "$_hrr_tmp"
    hw_schema_write "$_hrr_tmp"
    hw_atomic_write "$_hrr_tmp/source" "$_hrr_source"
    hw_atomic_write "$_hrr_tmp/source-id" "$_hrr_id"
    hw_atomic_write "$_hrr_tmp/ref-mode" "$_hrr_mode"
    hw_atomic_write "$_hrr_tmp/ref" "$_hrr_ref"
    hw_atomic_write "$_hrr_tmp/sha" "$_hrr_sha"
    rm -rf "$_hrr_dir"
    mv "$_hrr_tmp" "$_hrr_dir" || hw_die "cannot record repository realization"
}

hw_repo_gen_link() {
    _hrgl_ns=$1; _hrgl_id=$2; _hrgl_sha=$3; _hrgl_gen=$4
    mkdir -p "$_hrgl_gen/repos"
    # generations/<id>/repos is three levels below HW_DATA.
    _hrgl_rel="../../../git/checkouts/$_hrgl_id/$_hrgl_sha"
    hw_symlink_replace "$_hrgl_rel" "$_hrgl_gen/repos/$_hrgl_ns" || hw_die "cannot link repository into generation"
}

hw_repo_add_to_gen() {
    _hrag_source_input=$1; _hrag_ns=$2; _hrag_gen=$3; _hrag_ref_input=${4:-}
    hw_validate_name "$_hrag_ns" "repository namespace"
    _hrag_source=$(hw_repo_canonical_source "$_hrag_source_input") || hw_die "invalid repository source"
    _hrag_id=$(hw_repo_source_id "$_hrag_source")

    _hrag_existing="$(hw_repo_manifest_dir "$_hrag_gen")/$_hrag_ns"
    if [ -d "$_hrag_existing" ]; then
        _hrag_old_source=$(cat "$_hrag_existing/source")
        _hrag_old_mode=$(cat "$_hrag_existing/ref-mode")
        _hrag_old_ref=$(cat "$_hrag_existing/ref")
        _hrag_mode=default; [ -n "$_hrag_ref_input" ] && _hrag_mode=explicit
        if [ "$_hrag_old_source" != "$_hrag_source" ] || [ "$_hrag_old_mode" != "$_hrag_mode" ] || { [ "$_hrag_mode" = explicit ] && [ "$_hrag_old_ref" != "$_hrag_ref_input" ]; }; then
            hw_die "repository namespace $_hrag_ns has conflicting declarations in one generation"
        fi
        return 0
    fi

    _hrag_mode=default
    if [ -n "$_hrag_ref_input" ]; then
        _hrag_mode=explicit
        _hrag_ref=$_hrag_ref_input
    else
        _hrag_ref=$(hw_repo_default_ref "$_hrag_source") \
            || hw_die "repository has no usable default branch; pass --ref explicitly"
    fi
    hw_repo_validate_ref "$_hrag_ref"

    _hrag_lock=$(hw_repo_source_lock "$_hrag_id")
    hw_lock_acquire "$_hrag_lock" "repository source"
    if ! hw_repo_fetch_locked "$_hrag_source" "$_hrag_id"; then
        hw_lock_release "$_hrag_lock"
        hw_die "could not fetch repository source"
    fi
    _hrag_sha=$(hw_repo_resolve_locked "$_hrag_id" "$_hrag_ref") || {
        hw_lock_release "$_hrag_lock"
        hw_die "repository ref does not resolve to a unique commit"
    }
    hw_repo_checkout_locked "$_hrag_id" "$_hrag_sha" >/dev/null || {
        hw_lock_release "$_hrag_lock"
        hw_die "could not create repository checkout"
    }
    hw_repo_gen_link "$_hrag_ns" "$_hrag_id" "$_hrag_sha" "$_hrag_gen"
    hw_repo_record "$_hrag_ns" "$_hrag_source" "$_hrag_id" "$_hrag_mode" "$_hrag_ref" "$_hrag_sha" "$_hrag_gen"
    hw_lock_release "$_hrag_lock"
}

hw_repo_path() {
    _hrp_ns=$1
    hw_validate_name "$_hrp_ns" "repository namespace"
    if [ -n "${HOMEWORLD_TARGET:-}" ]; then _hrp_base=$HOMEWORLD_TARGET; else _hrp_base=$(hw_current); fi
    _hrp_path="$_hrp_base/repos/$_hrp_ns"
    [ -e "$_hrp_path" ] || [ -L "$_hrp_path" ] || return 1
    hw_managed_link_prepare_views "$_hrp_base"
    _hrp_projection="$(hw_resource_projections_dir "$_hrp_base")/repo/$_hrp_ns"
    if [ -f "$_hrp_projection" ]; then
        printf '%s/.homeworld/projections/%s' "$_hrp_base" "$(cat "$_hrp_projection")"
    else
        printf '%s' "$_hrp_path"
    fi
}

hw_repo_update_current() {
    _hruc_filter=${1:-}
    _hruc_gen=''
    [ -L "$(hw_current)" ] && _hruc_gen=$(readlink "$(hw_current)")
    [ -n "$_hruc_gen" ] || hw_die "no active generation"
    _hruc_root=$(hw_repo_manifest_dir "$_hruc_gen")
    [ -d "$_hruc_root" ] || return 0
    hw_schema_check "$_hruc_root" false
    _hruc_failed=0
    for _hruc_entry in "$_hruc_root"/*; do
        [ -d "$_hruc_entry" ] || continue
        _hruc_ns=$(basename "$_hruc_entry")
        [ -z "$_hruc_filter" ] || [ "$_hruc_filter" = "$_hruc_ns" ] || continue
        _hruc_source=$(cat "$_hruc_entry/source")
        _hruc_id=$(cat "$_hruc_entry/source-id")
        hw_repo_fetch_source "$_hruc_source" "$_hruc_id" || { hw_warn "could not update repository $_hruc_ns"; _hruc_failed=1; }
    done
    return "$_hruc_failed"
}

hw_repo_gc_locked() {
    _hrgc_live=$(mktemp)
    : > "$_hrgc_live"
    for _hrgc_gen in "$HW_DATA/generations"/*; do
        [ -d "$_hrgc_gen" ] || continue
        _hrgc_root=$(hw_repo_manifest_dir "$_hrgc_gen")
        [ -d "$_hrgc_root" ] || continue
        for _hrgc_entry in "$_hrgc_root"/*; do
            [ -d "$_hrgc_entry" ] || continue
            _hrgc_id=$(cat "$_hrgc_entry/source-id" 2>/dev/null) || continue
            _hrgc_sha=$(cat "$_hrgc_entry/sha" 2>/dev/null) || continue
            printf '%s/%s\n' "$_hrgc_id" "$_hrgc_sha" >> "$_hrgc_live"
        done
    done
    sort -u "$_hrgc_live" -o "$_hrgc_live"

    for _hrgc_source_dir in "$(hw_checkouts_dir)"/*; do
        [ -d "$_hrgc_source_dir" ] || continue
        _hrgc_id=$(basename "$_hrgc_source_dir")
        _hrgc_lock=$(hw_repo_source_lock "$_hrgc_id")
        hw_lock_acquire "$_hrgc_lock" "repository cleanup"
        for _hrgc_checkout in "$_hrgc_source_dir"/*; do
            [ -d "$_hrgc_checkout" ] || continue
            _hrgc_sha=$(basename "$_hrgc_checkout")
            if ! grep -qxF "$_hrgc_id/$_hrgc_sha" "$_hrgc_live"; then
                chmod -R u+w "$_hrgc_checkout" 2>/dev/null || true
                rm -rf "$_hrgc_checkout"
            fi
        done
        hw_lock_release "$_hrgc_lock"
    done

    _hrgc_now=$(date +%s 2>/dev/null || printf 0)
    _hrgc_grace=$((HW_MIRROR_GRACE_DAYS * 86400))
    mkdir -p "$(hw_orphaned_dir)"
    for _hrgc_mirror in "$(hw_mirrors_dir)"/*.git; do
        [ -d "$_hrgc_mirror" ] || continue
        _hrgc_id=$(basename "$_hrgc_mirror" .git)
        if grep -q "^$_hrgc_id/" "$_hrgc_live"; then
            rm -rf "$(hw_orphaned_dir)/$_hrgc_id"
            continue
        fi
        _hrgc_mark="$(hw_orphaned_dir)/$_hrgc_id"
        if [ ! -f "$_hrgc_mark/orphaned-at" ]; then
            mkdir -p "$_hrgc_mark"; hw_schema_write "$_hrgc_mark"; hw_atomic_write "$_hrgc_mark/orphaned-at" "$_hrgc_now"
            continue
        fi
        _hrgc_then=$(cat "$_hrgc_mark/orphaned-at" 2>/dev/null || printf "$_hrgc_now")
        if [ "$_hrgc_now" -gt 0 ] && [ $((_hrgc_now - _hrgc_then)) -ge "$_hrgc_grace" ]; then
            _hrgc_lock=$(hw_repo_source_lock "$_hrgc_id")
            hw_lock_acquire "$_hrgc_lock" "repository cleanup"
            rm -rf "$_hrgc_mirror" "$_hrgc_mark"
            hw_lock_release "$_hrgc_lock"
        fi
    done
    rm -f "$_hrgc_live"
}
