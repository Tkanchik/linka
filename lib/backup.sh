backup_user_config() {
    local name="$1"
    local path="$HOME/.config/$name"

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    if [[ -d "$path" && -z "$(ls -A "$path" 2>/dev/null || true)" ]]; then
        return 0
    fi

    if [[ -z "$CONFIG_BACKUP_DIR" ]]; then
        CONFIG_BACKUP_DIR="$BACKUP_BASE/configs.$(date +%Y%m%d_%H%M%S)"
        if ! mkdir -p "$CONFIG_BACKUP_DIR"; then
            log_warn "Не удалось создать каталог бэкапов $CONFIG_BACKUP_DIR"
            return 1
        fi
    fi

    if cp -a "$path" "$CONFIG_BACKUP_DIR/" 2>/dev/null; then
        log_info "Бэкап ~/.config/$name → $CONFIG_BACKUP_DIR/"
        return 0
    else
        log_warn "Не удалось сделать бэкап ~/.config/$name"
        return 1
    fi
}

rotate_backups() {
    local keep="$BACKUP_KEEP" prefix i
    local list=()

    if [[ ! "$keep" =~ ^[0-9]+$ ]]; then
        keep=5
    fi

    if [[ "$keep" -eq 0 || ! -d "$BACKUP_BASE" ]]; then
        return 0
    fi

    for prefix in update target configs removed; do
        list=()
        mapfile -t list < <(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -name "${prefix}.[0-9]*" 2>/dev/null | sort)

        if [[ ${#list[@]} -gt "$keep" ]]; then
            for ((i = 0; i < ${#list[@]} - keep; i++)); do
                rm -rf -- "${list[$i]}"
            done
            log_info "Старые бэкапы ${prefix}.*: оставлено $keep, удалено $((${#list[@]} - keep))"
        fi
    done

    return 0
}

backup_update_state() {
    local staging final pointer_tmp
    UPDATE_BACKUP_DIR=""
    [[ ! -L "$CONFIG_DIR" && ! -L "$STATE_DIR" && ! -L "$STATE_DIR/sounds" && ! -L "$BACKUP_BASE" ]] || return 1
    mkdir -p "$BACKUP_BASE" "$STATE_DIR" || return 1
    staging="$(mktemp -d "$BACKUP_BASE/.update.XXXXXXXX")" || return 1
    final="$BACKUP_BASE/update.$(date +%Y%m%d_%H%M%S).${staging##*.}"
    if ! mkdir -p "$staging/config" "$staging/sounds" "$staging/state" ||
       { [[ -e "$CONFIG_DIR" || -L "$CONFIG_DIR" ]] && ! cp -a "$CONFIG_DIR/." "$staging/config/"; } ||
       { [[ -e "$STATE_DIR/sounds" || -L "$STATE_DIR/sounds" ]] && ! cp -a "$STATE_DIR/sounds/." "$staging/sounds/"; } ||
       ! cp -a "$STATE_DIR/." "$staging/state/"; then
        rm -rf -- "$staging"
        log_error 'Не удалось сохранить настройки и состояние; обновление отменено.'
        return 1
    fi
    if ! printf 'version=%s\ncommit=%s\ntime=%s\n' "$OLD_VERSION" "$OLD_COMMIT" "$(date -Is)" > "$staging/manifest" ||
       ! : > "$staging/.complete" || ! mv -T -- "$staging" "$final"; then
        rm -rf -- "$staging"
        return 1
    fi
    pointer_tmp="$(mktemp "$STATE_DIR/.last-update-backup.XXXXXXXX")" || { rm -rf -- "$final"; return 1; }
    if ! printf '%s\n' "$final" > "$pointer_tmp" || ! mv -f -- "$pointer_tmp" "$STATE_DIR/.last-update-backup"; then
        rm -f -- "$pointer_tmp"
        rm -rf -- "$final"
        return 1
    fi
    UPDATE_BACKUP_DIR="$final"
    return 0
}

restore_update_config() {
    if [[ -z "$UPDATE_BACKUP_DIR" || ! -f "$UPDATE_BACKUP_DIR/.complete" ]]; then
        return 0
    fi

    restore_snapshot_tree "$UPDATE_BACKUP_DIR/config" "$CONFIG_DIR"
}

restore_update_sounds() {
    if [[ -z "$UPDATE_BACKUP_DIR" || ! -f "$UPDATE_BACKUP_DIR/.complete" ]]; then
        return 0
    fi

    restore_snapshot_tree "$UPDATE_BACKUP_DIR/sounds" "$STATE_DIR/sounds"
}

restore_snapshot_tree() {
    local snapshot="$1" destination="$2" list path relative original
    [[ -d "$snapshot" && ! -L "$snapshot" && ! -L "$destination" ]] || return 1
    mkdir -p -- "$destination" || return 1
    list="$(mktemp)" || return 1
    if ! find "$destination" -depth -mindepth 1 -print0 > "$list"; then
        rm -f -- "$list"
        return 1
    fi
    while IFS= read -r -d '' path; do
        relative="${path#"$destination"/}"
        if [[ "$destination" == "$STATE_DIR" && ( "$relative" == .linka-journal || "$relative" == .linka-rollback ) ]]; then
            continue
        fi
        original="$snapshot/$relative"
        if [[ ! -e "$original" && ! -L "$original" ]] ||
           [[ "$(stat -c %F -- "$path")" != "$(stat -c %F -- "$original")" ]]; then
            rm -rf -- "$path" || { rm -f -- "$list"; return 1; }
        fi
    done < "$list"
    rm -f -- "$list"
    cp -a --remove-destination -- "$snapshot/." "$destination/"
}

sync_sounds_from_repo() {
    local repo="$1"
    local dst="$STATE_DIR/sounds"
    local src="$repo/src/assets/sounds"

    [[ ! -L "$dst" ]] || return 1
    mkdir -p "$dst" || return 1

    if [[ -d "$src" ]]; then
        cp -a "$src/." "$dst/" || return 1
    fi

    if [[ -n "$UPDATE_BACKUP_DIR" && -d "$UPDATE_BACKUP_DIR/sounds" ]]; then
        cp -a "$UPDATE_BACKUP_DIR/sounds/." "$dst/" || return 1
    fi

    return 0
}
