linka_stage_shell() {
    local repo="$1" stage="$2" path parent part prefix old
    [[ -d "$TARGET_BASE" ]] || return 1
    if [[ -d "$TARGET_BASE" ]]; then
        cp -a --reflink=auto "$TARGET_BASE/." "$stage/" || return 1
    fi
    if [[ -n "$OLD_COMMIT" && "$OLD_COMMIT" != unknown ]] && git -C "$repo" cat-file -e "${OLD_COMMIT}^{commit}" 2>/dev/null; then
        while IFS= read -r -d '' old; do
            rm -rf -- "${stage:?}/$old" || return 1
        done < <(git -C "$repo" diff -z --name-only --no-renames --diff-filter=D "$OLD_COMMIT" HEAD -- bin src)
    fi
    while IFS= read -r -d '' path; do
        parent="${path%/*}"
        prefix="$stage"
        while IFS= read -r part; do
            [[ -n "$part" ]] || continue
            prefix="$prefix/$part"
            if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) ]]; then
                rm -f -- "$prefix" || return 1
            fi
            mkdir -p -- "$prefix" || return 1
        done < <(tr '/' '\n' <<< "$parent")
        rm -rf -- "${stage:?}/$path" || return 1
        cp -a -- "$repo/$path" "$stage/$path" || return 1
    done < <(git -C "$repo" ls-files -z -- bin src)
    if [[ -f "$repo/version.txt" ]]; then
        cp -a --remove-destination -- "$repo/version.txt" "$stage/version.txt" || return 1
    fi
    if [[ ! -f "$stage/.serpantinum-managed" ]]; then
        printf 'owner=linka\nversion=%s\nrepo=%s\n' "$LINKA_VERSION" "$REPO_SLUG" > "$stage/.serpantinum-managed" || return 1
    fi
    (
        TARGET_BASE="$stage"
        fix_exec_bits
        verify_deploy "$repo"
    )
}

linka_journal_write() {
    local previous="$1" next="$2" backup="$3" was="$4" temp
    temp="$(mktemp "$STATE_DIR/.linka-journal.XXXXXXXX")" || return 1
    if ! printf '%s\n%s\n%s\n%s\n' "$previous" "$next" "$backup" "$was" > "$temp" ||
       ! mv -f -- "$temp" "$STATE_DIR/.linka-journal"; then
        rm -f -- "$temp"
        return 1
    fi
}

linka_switch_generation() {
    local next="$1" temp="$TARGET_BASE.linka-next.$$"
    [[ -d "$next" && ! -L "$next" ]] || return 1
    ln -s -- "$next" "$temp" || return 1
    if [[ -d "$TARGET_BASE" && ! -L "$TARGET_BASE" ]]; then
        rm -f -- "$temp"
        return 1
    fi
    if ! mv -fT -- "$temp" "$TARGET_BASE"; then
        rm -f -- "$temp"
        return 1
    fi
}

restore_update_state() {
    [[ -n "$UPDATE_BACKUP_DIR" && -f "$UPDATE_BACKUP_DIR/.complete" ]] || return 1
    restore_snapshot_tree "$UPDATE_BACKUP_DIR/state" "$STATE_DIR"
}

linka_restore_transaction() {
    local previous="$1" was="$2" failed=0
    if [[ -d "$previous" ]]; then
        stop_shell || true
        linka_switch_generation "$previous" || failed=1
    elif [[ ! -d "$TARGET_BASE" ]]; then
        failed=1
    fi
    restore_update_config || failed=1
    restore_update_sounds || failed=1
    restore_update_state || failed=1
    if [[ "$was" == 1 ]]; then
        start_shell_unless_idle 1 || failed=1
    fi
    if [[ "$failed" -eq 0 ]]; then
        rm -f -- "$STATE_DIR/.linka-journal"
        log_warn 'Предыдущее поколение Serpantinum и настройки восстановлены.'
        return 0
    fi
    log_error "Автоматическое восстановление не завершено. Журнал: $STATE_DIR/.linka-journal"
    return 1
}

linka_recover_transaction() {
    local journal="$STATE_DIR/.linka-journal" previous next backup was
    [[ -f "$journal" ]] || return 0
    mapfile -t _linka_journal < "$journal"
    previous="${_linka_journal[0]:-}"
    next="${_linka_journal[1]:-}"
    backup="${_linka_journal[2]:-}"
    was="${_linka_journal[3]:-0}"
    [[ "$(realpath -m -- "$previous")" == "$GENERATIONS_BASE"/* &&
       "$(realpath -m -- "$next")" == "$GENERATIONS_BASE"/* &&
       "$(realpath -m -- "$backup")" == "$BACKUP_BASE"/* ]] || return 1
    UPDATE_BACKUP_DIR="$backup"
    linka_restore_transaction "$previous" "$was"
}

linka_health_check() {
    local generation="$1" i
    for i in 1 2 3 4 5; do
        sleep 1
        pgrep -f "$generation/src/quickshell" >/dev/null 2>&1 || return 1
    done
    return 0
}

linka_prune_generations() {
    local current="$1" previous="$2" path
    while IFS= read -r -d '' path; do
        [[ "$path" == "$current" || "$path" == "$previous" ]] && continue
        rm -rf -- "$path" || return 1
    done < <(find "$GENERATIONS_BASE" -mindepth 1 -maxdepth 1 -type d -print0)
}

linka_update_session_ready() {
    auto_adopt_session_env || true
    if [[ -z "${WAYLAND_DISPLAY:-}" || -z "${XDG_RUNTIME_DIR:-}" || ! -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
        log_error 'Для безопасного обновления нужна активная графическая сессия Wayland. Повторите linka update из неё.'
        return 1
    fi
}

transactional_deploy_update() {
    local repo="$1" next previous was=0
    mkdir -p "$GENERATIONS_BASE" || return 1
    next="$(mktemp -d "$GENERATIONS_BASE/generation.XXXXXXXX")" || return 1
    if ! linka_stage_shell "$repo" "$next"; then
        rm -rf -- "$next"
        return 1
    fi
    backup_update_state || { rm -rf -- "$next"; return 1; }
    if ! (TARGET_DIR="$next" TARGET_BASE="$next"; fix_matugen_compat && run_user_post_update_hook); then
        restore_update_config || log_error 'Настройки после ошибки хука не восстановлены.'
        restore_update_sounds || log_error 'Звуки после ошибки хука не восстановлены.'
        restore_update_state || log_error 'Состояние после ошибки хука не восстановлено.'
        rm -rf -- "$next"
        return 1
    fi
    if shell_running; then was=1; fi
    if [[ -L "$TARGET_BASE" ]]; then
        previous="$(readlink -f -- "$TARGET_BASE")" || return 1
    else
        previous="$(mktemp -d "$GENERATIONS_BASE/previous.XXXXXXXX")" || return 1
        rmdir -- "$previous" || return 1
    fi
    linka_journal_write "$previous" "$next" "$UPDATE_BACKUP_DIR" "$was" || return 1
    if [[ "$was" == 1 ]] && ! stop_shell; then
        rm -f -- "$STATE_DIR/.linka-journal"
        log_error 'Оболочка не остановилась; переключение отменено.'
        return 1
    fi
    if [[ ! -L "$TARGET_BASE" ]]; then
        if ! mv -- "$TARGET_BASE" "$previous" || ! ln -s -- "$previous" "$TARGET_BASE"; then
            linka_restore_transaction "$previous" "$was" || true
            return 1
        fi
    fi
    if ! linka_switch_generation "$next"; then
        linka_restore_transaction "$previous" "$was" || true
        return 1
    fi
    if ! sync_sounds_from_repo "$repo" ||
       ! merge_serpantinum_config "$repo" ||
       ! start_shell ||
       ! linka_health_check "$next" ||
       ! mark_shell_state ||
       ! write_version_file; then
        linka_restore_transaction "$previous" "$was" || true
        return 1
    fi
    if [[ "$was" == 0 ]]; then
        stop_shell || log_warn 'Проверочная оболочка продолжает работать.'
    fi
    printf '%s\n%s\n' "$previous" "$UPDATE_BACKUP_DIR" > "$STATE_DIR/.linka-rollback" || return 1
    rm -f -- "$STATE_DIR/.linka-journal"
    linka_prune_generations "$next" "$previous" || log_warn 'Не удалось удалить старые поколения оболочки.'
    log_ok "Обновлён: $TARGET_VERSION ($TARGET_COMMIT)."
    return 0
}

linka_rollback() {
    local record="$STATE_DIR/.linka-rollback" previous backup current was=0
    [[ -f "$record" ]] || { log_error 'Нет сохранённого поколения для отката.'; return 1; }
    mapfile -t _linka_rollback < "$record"
    previous="${_linka_rollback[0]:-}"
    backup="${_linka_rollback[1]:-}"
    [[ "$(realpath -m -- "$previous")" == "$GENERATIONS_BASE"/* && -d "$previous" &&
       "$(realpath -m -- "$backup")" == "$BACKUP_BASE"/* && -f "$backup/.complete" ]] || return 1
    [[ -L "$TARGET_BASE" ]] || return 1
    current="$(readlink -f -- "$TARGET_BASE")" || return 1
    UPDATE_BACKUP_DIR="$backup"
    if shell_running; then was=1; fi
    linka_journal_write "$previous" "$current" "$backup" "$was" || return 1
    if [[ "$was" == 1 ]]; then stop_shell || return 1; fi
    if ! linka_switch_generation "$previous" ||
       ! restore_update_config || ! restore_update_sounds || ! restore_update_state ||
       { [[ "$was" == 1 ]] && ! start_shell_unless_idle 1; }; then
        log_error "Откат не завершён. Сохранён журнал: $STATE_DIR/.linka-journal"
        return 1
    fi
    rm -f -- "$STATE_DIR/.linka-journal" "$record"
    linka_prune_generations "$previous" "$previous" || log_warn 'Не удалось удалить отменённое поколение.'
    log_ok 'Файлы оболочки и настройки восстановлены. Пакеты ОС не изменялись.'
}
