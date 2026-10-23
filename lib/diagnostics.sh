linka_doctor() {
    local pkg comp version failed=0 installed=0
    local comps=()
    if [[ -f "$STATE_FILE" ]]; then
        local saved
        saved="$(state_get SELECTED_COMPOSITORS)"
        read -r -a comps <<< "$saved"
    fi
    printf 'linka %s · диагностика\n' "$LINKA_VERSION"
    printf 'Система: %s\n' "${DISTRO:-не определена}"
    if [[ -L "$TARGET_BASE" ]]; then
        printf 'Поколение: %s\n' "$(readlink -f -- "$TARGET_BASE")"
        installed=1
    elif [[ -d "$TARGET_BASE" ]]; then
        printf 'Установка: обычный каталог\n'
        installed=1
    else
        printf 'Установка: отсутствует\n'
    fi
    if [[ -f "$STATE_DIR/.linka-journal" ]]; then
        printf 'Восстановление: есть незавершённая операция\n'
        failed=1
    fi
    if [[ -f "$STATE_DIR/.linka-rollback" ]]; then
        printf 'Откат: доступен\n'
    fi
    for pkg in "${CORE_PKGS[@]}"; do
        if pkg_installed "$pkg"; then
            printf 'Пакет %s: установлен\n' "$pkg"
        else
            printf 'Пакет %s: отсутствует\n' "$pkg"
            failed=1
        fi
    done
    if command -v quickshell >/dev/null 2>&1; then
        version="$(quickshell_version)"
        if [[ -n "$version" ]] && version_ge "$version" "$QUICKSHELL_MIN_VERSION"; then
            printf 'Quickshell: %s\n' "$version"
        else
            printf 'Quickshell: несовместимая или неизвестная версия\n'
            failed=1
        fi
    else
        printf 'Quickshell: отсутствует\n'
        failed=1
    fi
    for comp in "${comps[@]}"; do
        if is_compositor_installed "$comp"; then
            printf 'Композитор %s: установлен\n' "$comp"
        else
            printf 'Композитор %s: отсутствует\n' "$comp"
            failed=1
        fi
    done
    if [[ "$installed" == 1 ]]; then
        printf 'Коммит: %s\n' "$(state_get SHELL_COMMIT)"
    fi
    printf 'Бэкапы: %s\n' "$BACKUP_BASE"
    return "$failed"
}

linka_dry_run() {
    local operation="$1" target='неизвестен'
    if [[ -d "$CACHE_BASE/.git" ]]; then
        target="$(git -C "$CACHE_BASE" rev-parse --short HEAD 2>/dev/null || printf 'неизвестен')"
    fi
    printf 'Предпросмотр: %s\n' "$operation"
    printf 'Текущий коммит: %s\n' "$(state_get SHELL_COMMIT)"
    printf 'Доступный коммит в локальном кэше: %s\n' "$target"
    case "$operation" in
        install|reinstall)
            printf 'Шаги: проверка зависимостей → бэкап → подготовка файлов → настройка → запуск\n'
            ;;
        update)
            printf 'Шаги: проверка сессии и зависимостей → подготовка поколения → бэкап → переключение → проверка запуска\n'
            ;;
        rollback)
            printf 'Шаги: остановка оболочки → прежнее поколение → восстановление настроек → запуск\n'
            ;;
        remove)
            printf 'Шаги: бэкап настроек → остановка → удаление управляемых файлов и служб\n'
            ;;
    esac
    linka_doctor || true
    printf 'Изменений не внесено.\n'
}

linka_operation_summary() {
    local operation="$1" status="$2" label backup='нет' journal='нет'
    case "$operation" in
        install) label='Установка' ;;
        reinstall) label='Переустановка' ;;
        update) label='Обновление' ;;
        rollback) label='Откат' ;;
        remove) label='Удаление' ;;
        *) label="$operation" ;;
    esac
    if [[ "$status" == 0 ]]; then
        printf '%s: завершено\n' "$label"
        printf 'Пропущено: нет обязательных шагов\n'
    else
        printf '%s: ошибка (код %s)\n' "$label" "$status"
        printf 'Пропущено: оставшиеся шаги операции\n'
    fi
    if [[ -n "${UPDATE_BACKUP_DIR:-}" && -d "$UPDATE_BACKUP_DIR" ]]; then
        backup="$UPDATE_BACKUP_DIR"
    elif [[ -f "$STATE_DIR/.last-update-backup" ]]; then
        backup="$(cat "$STATE_DIR/.last-update-backup")"
    fi
    if [[ -f "$STATE_DIR/.linka-journal" ]]; then
        journal="$STATE_DIR/.linka-journal"
    fi
    printf 'Бэкап: %s\nЖурнал: %s\n' "$backup" "$journal"
    if [[ ${#FAILED_PKGS[@]} -gt 0 ]]; then
        printf 'Проблемы с пакетами: %s\n' "${FAILED_PKGS[*]}"
    fi
}

linka_run_reported() {
    local operation="$1" status=0
    shift
    "$@" || status=$?
    linka_operation_summary "$operation" "$status"
    return "$status"
}
