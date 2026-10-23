serialize_array() {
    if [[ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]]; then
        printf ''
        return 0
    fi

    local IFS=' '
    printf '%s' "${SELECTED_COMPOSITORS[*]}"
    return 0
}

state_get() {
    if [[ ! -f "$STATE_FILE" ]]; then
        return 0
    fi

    K="$1" awk -F= 'BEGIN{k=ENVIRON["K"]} $1==k{sub(/^[^=]*=/,""); print; exit}' "$STATE_FILE"
    return 0
}

update_state_field() {
    local key="$1"
    local safe_value
    local tmp

    mkdir -p "$STATE_DIR"
    safe_value="$(printf '%s' "$2" | tr '\n\r' '  ')"
    tmp="$(mktemp "${STATE_DIR}/.state.XXXXXX")"

    if [[ -f "$STATE_FILE" ]]; then
        K="$key" V="$safe_value" awk -F= '
            BEGIN{f=0; k=ENVIRON["K"]; v=ENVIRON["V"]}
            $1==k{print k"="v; f=1; next}
            {print}
            END{if(!f) print k"="v}
        ' "$STATE_FILE" > "$tmp"
    else
        printf '%s=%s\n' "$key" "$safe_value" > "$tmp"
    fi

    chmod 600 "$tmp"
    mv -f "$tmp" "$STATE_FILE"
    return 0
}

load_state() {
    OLD_VERSION="$(state_get SERPANTINUM_VERSION || true)"
    OLD_COMMIT="$(state_get SHELL_COMMIT || true)"
    if [[ -z "$OLD_COMMIT" ]]; then
        OLD_COMMIT="unknown"
    fi

    local saved v
    saved="$(state_get SELECTED_COMPOSITORS || true)"
    SELECTED_COMPOSITORS_SAVED=()
    if [[ -n "$saved" ]]; then
        read -r -a SELECTED_COMPOSITORS_SAVED <<< "$saved"
    fi

    v="$(state_get OPT_SDDM || true)"
    if [[ "$v" == true || "$v" == false ]]; then
        OPT_SDDM="$v"
    fi

    v="$(state_get INSTALL_FULL_WALLPAPERS || true)"
    if [[ "$v" == true || "$v" == false ]]; then
        INSTALL_FULL_WALLPAPERS="$v"
    fi

    return 0
}

read_version_file() {
    if [[ ! -f "$1" ]]; then
        return 0
    fi

    grep -m1 -oE '[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.]+)?' "$1" 2>/dev/null || true
    return 0
}

get_installed_version() {
    local ver
    ver="$(state_get SERPANTINUM_VERSION || true)"

    if [[ -z "$ver" ]]; then
        ver="$(read_version_file "$STATE_DIR/version")"
    fi

    if [[ -z "$ver" ]]; then
        ver="$(read_version_file "$TARGET_BASE/src/version.txt")"
    fi

    if [[ -z "$ver" ]]; then
        ver="$(read_version_file "$TARGET_BASE/version.txt")"
    fi

    if [[ -z "$ver" ]]; then
        ver="$DEFAULT_FALLBACK_VERSION"
    fi

    printf '%s\n' "$ver"
    return 0
}

get_installed_commit() {
    local c
    c="$(state_get SHELL_COMMIT || true)"

    if [[ -z "$c" && -f "$STATE_DIR/version" ]]; then
        c="$(awk -F= '/^SERPANTINUM_COMMIT=/{gsub(/"/,"",$2); print $2; exit}' "$STATE_DIR/version" 2>/dev/null || true)"
    fi

    printf '%s\n' "${c:-unknown}"
    return 0
}

fetch_remote_version() {
    curl -fsSL --connect-timeout 10 --retry 2 "$1" 2>/dev/null \
        | grep -m1 -oE '[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.]+)?' || true
    return 0
}

get_target_version() {
    local root="$1"
    local v=""
    local branch="${ACTIVE_REPO_BRANCH:-${REPO_BRANCH:-master}}"
    local base="https://raw.githubusercontent.com/${REPO_SLUG}"

    v="$(read_version_file "$root/src/version.txt")"
    if [[ -z "$v" ]]; then
        v="$(read_version_file "$root/version.txt")"
    fi

    if command -v curl >/dev/null 2>&1; then
        if [[ -z "$v" ]]; then v="$(fetch_remote_version "$base/${branch}/src/version.txt")"; fi
        if [[ -z "$v" ]]; then v="$(fetch_remote_version "$base/HEAD/src/version.txt")"; fi
        if [[ -z "$v" ]]; then v="$(fetch_remote_version "$base/${branch}/version.txt")"; fi
        if [[ -z "$v" ]]; then v="$(fetch_remote_version "$base/HEAD/version.txt")"; fi
    fi

    if [[ -z "$v" || "$v" == null ]]; then
        v="$DEFAULT_FALLBACK_VERSION"
    fi

    printf '%s\n' "$v"
    return 0
}

get_target_commit() {
    local c=""
    local branch="${ACTIVE_REPO_BRANCH:-${REPO_BRANCH:-master}}"

    if [[ -d "$1/.git" ]]; then
        c="$(git -C "$1" rev-parse --short HEAD 2>/dev/null || true)"
    fi

    if [[ -z "$c" ]] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        c="$(curl -fsSL --connect-timeout 10 --retry 2 \
            "https://api.github.com/repos/${REPO_SLUG}/commits/${branch}" 2>/dev/null \
            | jq -r '.sha[:7] // empty' 2>/dev/null || true)"
    fi

    if [[ -z "$c" ]] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        c="$(curl -fsSL --connect-timeout 10 --retry 2 \
            "https://api.github.com/repos/${REPO_SLUG}/commits/HEAD" 2>/dev/null \
            | jq -r '.sha[:7] // empty' 2>/dev/null || true)"
    fi

    printf '%s\n' "${c:-unknown}"
    return 0
}

mark_shell_state() {
    update_state_field SERPANTINUM_VERSION "$TARGET_VERSION" || return 1
    update_state_field SHELL_VERSION "$TARGET_VERSION" || return 1
    update_state_field SHELL_COMMIT "$TARGET_COMMIT" || return 1
    update_state_field SELECTED_COMPOSITORS "$(serialize_array)" || return 1
    update_state_field OPT_SDDM "$OPT_SDDM" || return 1
    update_state_field INSTALL_FULL_WALLPAPERS "$INSTALL_FULL_WALLPAPERS" || return 1
    return 0
}

is_installed() {
    if [[ -f "$OWNERSHIP_MARKER" && -f "$STATE_FILE" ]]; then
        return 0
    fi

    if [[ -f "$TARGET_BASE/bin/serpantinumd" || -d "$TARGET_BASE/src/quickshell" ]]; then
        return 0
    fi

    return 1
}

detect_install_state() {
    if is_installed; then
        printf 'current\n'
        return 0
    fi
    printf 'fresh\n'
    return 0
}

protect_local_repo_changes() {
    local ts msg status_out
    status_out="$(git -C "$CACHE_BASE" status --porcelain 2>/dev/null || true)"
    if [[ -z "$status_out" ]]; then
        return 0
    fi

    ts="$(date +%Y%m%d_%H%M%S)"
    msg="linka-auto-${ts}"

    if git -c user.name=linka -c user.email=linka@localhost -C "$CACHE_BASE" \
        stash push -u -m "$msg" >/dev/null 2>&1; then
        log_warn "В $CACHE_BASE были локальные изменения — сохранены: git -C $CACHE_BASE stash list ($msg)"
        return 0
    fi

    if echo "$status_out" | grep -q '^\?\?'; then
        log_error "В $CACHE_BASE есть неотслеживаемые файлы, но git stash не сработал. Сброс репозитория отменён во избежание потери данных."
        return 1
    fi

    mkdir -p "$BACKUP_BASE"
    if git -C "$CACHE_BASE" diff HEAD > "$BACKUP_BASE/repo-local-changes.${ts}.patch" 2>/dev/null && [[ -s "$BACKUP_BASE/repo-local-changes.${ts}.patch" ]]; then
        log_warn "В $CACHE_BASE были локальные изменения — diff сохранён в $BACKUP_BASE/repo-local-changes.${ts}.patch"
        return 0
    else
        log_error "В $CACHE_BASE есть локальные изменения, но сохранить их не удалось. Сброс репозитория отменён."
        return 1
    fi
}

ensure_repo() {
    require_command git

    local ref="" branch="$REPO_BRANCH" b

    if [[ ! -d "$CACHE_BASE/.git" ]]; then
        if [[ -e "$CACHE_BASE" && -n "$(ls -A "$CACHE_BASE" 2>/dev/null || true)" ]]; then
            mkdir -p "$BACKUP_BASE"
            mv "$CACHE_BASE" "${BACKUP_BASE}/serpantinum-dir.$(date +%Y%m%d_%H%M%S)"
        fi

        mkdir -p "$CACHE_BASE"
        git clone "https://github.com/${REPO_SLUG}.git" "$CACHE_BASE" || {
            log_error 'Не удалось клонировать репозиторий.'
            return 1
        }
    else
        git -C "$CACHE_BASE" remote set-url origin "https://github.com/${REPO_SLUG}.git" || true
        git -C "$CACHE_BASE" fetch --prune origin || log_warn 'git fetch не удался, использую локальное состояние репо'
    fi

    if [[ -n "$branch" ]] && git -C "$CACHE_BASE" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        ref="origin/$branch"
    else
        ref="$(git -C "$CACHE_BASE" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"

        if [[ -z "$ref" ]]; then
            for b in master main; do
                if git -C "$CACHE_BASE" show-ref --verify --quiet "refs/remotes/origin/$b"; then
                    ref="origin/$b"
                    break
                fi
            done
        fi
    fi

    if [[ -z "$ref" ]]; then
        log_error 'Не удалось определить ветку обновления репозитория.'
        return 1
    fi

    protect_local_repo_changes || return 1
    git -C "$CACHE_BASE" reset --hard "$ref" || return 1

    ACTIVE_REPO_BRANCH="${ref#origin/}"
    PROJECT_ROOT="$CACHE_BASE"

    return 0
}

prepare_environment() {
    acquire_lock
    start_sudo_keepalive
    bootstrap_installer_deps
    ensure_repo
}

write_version_file() {
    local vf="$STATE_DIR/version" tel_id="" tel_en="" tmp

    mkdir -p "$STATE_DIR"

    if [[ -f "$vf" ]]; then
        tel_id="$(awk -F= '/^TELEMETRY_ID=/{gsub(/"/,"",$2); print $2; exit}' "$vf" 2>/dev/null || true)"
        tel_en="$(awk -F= '/^ENABLE_TELEMETRY=/{gsub(/"/,"",$2); print $2; exit}' "$vf" 2>/dev/null || true)"
    fi

    tmp="$(mktemp "$STATE_DIR/.version.XXXXXX")" || return 1

    {
        printf 'SERPANTINUM_VERSION="%s"\n' "$TARGET_VERSION"
        printf 'SERPANTINUM_COMMIT="%s"\n' "$TARGET_COMMIT"
        if [[ -n "$tel_id" ]]; then printf 'TELEMETRY_ID="%s"\n' "$tel_id"; fi
        if [[ -n "$tel_en" ]]; then printf 'ENABLE_TELEMETRY="%s"\n' "$tel_en"; fi
        printf 'SELECTED_COMPOSITORS="%s"\n' "$(serialize_array)"
    } > "$tmp"

    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$vf"
    return 0
}
