auto_get() {
    local v=""
    if [[ -f "$AUTO_CONF" ]]; then
        v="$(K="$1" awk -F= 'BEGIN{k=ENVIRON["K"]} $1==k{sub(/^[^=]*=/,""); print; exit}' "$AUTO_CONF" 2>/dev/null || true)"
    fi
    printf '%s\n' "${v:-${2:-}}"
    return 0
}

auto_set() {
    local key="$1" val tmp
    val="$(printf '%s' "$2" | tr '\n\r' '  ')"
    mkdir -p "$STATE_DIR"
    tmp="$(mktemp "$STATE_DIR/.auto.XXXXXX")"

    if [[ -f "$AUTO_CONF" ]]; then
        K="$key" V="$val" awk -F= '
            BEGIN{f=0; k=ENVIRON["K"]; v=ENVIRON["V"]}
            $1==k{print k"="v; f=1; next}
            {print}
            END{if(!f) print k"="v}
        ' "$AUTO_CONF" > "$tmp"
    else
        printf '%s=%s\n' "$key" "$val" > "$tmp"
    fi

    chmod 600 "$tmp"
    mv -f "$tmp" "$AUTO_CONF"
    return 0
}

auto_valid_mode() {
    case "$1" in
        off|notify|apply) return 0 ;;
    esac
    return 1
}

auto_valid_uint() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$((10#$1))" -gt 0 ]]
}

auto_notify() {
    if [[ "$(auto_get AUTO_NOTIFY 1)" != 1 ]]; then
        return 0
    fi
    if ! command -v notify-send >/dev/null 2>&1; then
        return 0
    fi
    notify-send -a linka -u "${3:-normal}" "$1" "$2" >/dev/null 2>&1 || true
    return 0
}

auto_setup_log() {
    local sz
    mkdir -p "$STATE_DIR"

    if [[ -f "$AUTO_LOG" ]]; then
        sz="$(stat -c %s "$AUTO_LOG" 2>/dev/null || echo 0)"
        if [[ "$sz" -gt "$AUTO_LOG_MAX" ]]; then
            mv -f "$AUTO_LOG" "$AUTO_LOG.1" 2>/dev/null || true
        fi
    fi

    exec >>"$AUTO_LOG" 2>&1
    return 0
}

acquire_lock_quiet() {
    if ! command -v flock >/dev/null 2>&1; then
        return 0
    fi

    exec 9>"$LOCK_FILE" || return 0

    if ! flock -n 9; then
        exec 9>&- 2>/dev/null || true
        return 1
    fi

    return 0
}

auto_network_ok() {
    curl -fsSI --connect-timeout 5 --max-time 15 https://github.com >/dev/null 2>&1
}

auto_adopt_session_env() {
    local pid="" line

    pid="$(pgrep -f "$TARGET_BASE/src/quickshell" 2>/dev/null | head -n1 || true)"
    if [[ -z "$pid" ]]; then
        pid="$({ pgrep -f "$TARGET_BASE/bin/serpantinumd" || pgrep -f "$BIN_DIR/serpantinumd"; } 2>/dev/null | head -n1 || true)"
    fi
    if [[ -z "$pid" ]]; then
        pid="$({ pgrep -x niri || pgrep -x Hyprland || pgrep -x sway || pgrep -x mango; } 2>/dev/null | head -n1 || true)"
    fi

    if [[ -z "$pid" || ! -r "/proc/$pid/environ" ]]; then
        return 1
    fi

    while IFS= read -r -d '' line; do
        case "$line" in
            WAYLAND_DISPLAY=*|DISPLAY=*|XDG_RUNTIME_DIR=*|XDG_CURRENT_DESKTOP=*|\
            XDG_SESSION_TYPE=*|DESKTOP_SESSION=*|DBUS_SESSION_BUS_ADDRESS=*|\
            HYPRLAND_INSTANCE_SIGNATURE=*|SWAYSOCK=*|NIRI_SOCKET=*|MANGO_INSTANCE_SIGNATURE=*|QT_QPA_PLATFORM=*)
                export "${line?}"
                ;;
        esac
    done < "/proc/$pid/environ" || true

    return 0
}

start_shell_unless_idle() {
    if [[ "$AUTO_MODE" == 1 && "${1:-1}" == 0 ]]; then
        log_info 'Шелл не был запущен — не стартую.'
        return 0
    fi
    start_shell
}

auto_shell_step() {
    local mode="$1" failed notified

    if ! is_installed; then
        log_info 'Serpantinum не установлен — пропускаю (в фоне ничего не ставлю).'
        return 0
    fi

    REPO_BRANCH="$(auto_get AUTO_BRANCH "$REPO_BRANCH")"

    if ! ensure_repo; then
        log_warn 'Serpantinum: репозиторий недоступен — пропускаю.'
        return 0
    fi

    load_state
    init_compositor_detection

    OLD_COMMIT="$(get_installed_commit)"
    OLD_VERSION="$(get_installed_version)"
    TARGET_COMMIT="$(get_target_commit "$PROJECT_ROOT")"
    TARGET_VERSION="$(get_target_version "$PROJECT_ROOT")"

    if [[ "$TARGET_COMMIT" == unknown || "$OLD_COMMIT" == "$TARGET_COMMIT" ]]; then
        log_info "Serpantinum актуален ($OLD_VERSION, $OLD_COMMIT)."
        return 0
    fi

    log_info "Serpantinum: доступно $OLD_VERSION ($OLD_COMMIT) -> $TARGET_VERSION ($TARGET_COMMIT)"

    if [[ "$mode" == notify ]]; then
        notified="$(auto_get AUTO_NOTIFIED_COMMIT '')"
        if [[ "$notified" != "$TARGET_COMMIT" ]]; then
            auto_notify 'Serpantinum: есть обновление' "$OLD_VERSION → $TARGET_VERSION. Применить: linka update"
            auto_set AUTO_NOTIFIED_COMMIT "$TARGET_COMMIT"
        fi
        return 0
    fi

    failed="$(auto_get AUTO_FAILED_COMMIT '')"
    if [[ "$failed" == "$TARGET_COMMIT" ]]; then
        log_info "Прошлая попытка обновиться на $TARGET_COMMIT не удалась — не повторяю (linka update вручную)."
        return 0
    fi

    auto_adopt_session_env || log_info 'Окружение сессии не найдено; проверю возможность безопасного обновления.'
    auto_notify 'Serpantinum' "Обновляю: $OLD_VERSION → $TARGET_VERSION"

    if linka_run_reported update flow_update; then
        auto_set AUTO_FAILED_COMMIT ''
        auto_notify 'Serpantinum обновлён' "$TARGET_VERSION ($TARGET_COMMIT)"
    else
        auto_set AUTO_FAILED_COMMIT "$TARGET_COMMIT"
        auto_notify 'Serpantinum: обновление не удалось' "Подробности: $AUTO_LOG" critical
    fi

    return 0
}

auto_on_battery() {
    local d t online have_ac=0 have_bat=0

    for d in /sys/class/power_supply/*; do
        if [[ ! -r "$d/type" ]]; then
            continue
        fi
        t="$(cat "$d/type" 2>/dev/null || true)"
        case "$t" in
            Battery)
                have_bat=1
                ;;
            Mains)
                online="$(cat "$d/online" 2>/dev/null || echo 0)"
                if [[ "$online" == 1 ]]; then
                    have_ac=1
                fi
                ;;
        esac
    done

    [[ "$have_bat" == 1 && "$have_ac" == 0 ]]
}

auto_system_due() {
    local every last now
    every="$(auto_get AUTO_SYSTEM_EVERY_DAYS 1)"
    last="$(auto_get AUTO_LAST_SYSTEM 0)"
    now="$(date +%s)"

    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    [[ "$every" =~ ^[0-9]+$ ]] || every=1

    (( now - 10#$last >= 10#$every * 86400 ))
}

sudoers_escape() {
    printf '%s' "$1" | sed -e 's/[,:=\\]/\\&/g'
}

auto_privileged_commands() {
    local mode="$1" bin

    if [[ "$mode" == off ]]; then
        return 0
    fi

    if [[ "$DISTRO" == fedora ]]; then
        if [[ "$mode" == apply ]]; then
            bin="$(command -v dnf 2>/dev/null || command -v dnf5 2>/dev/null || true)"
            if [[ -n "$bin" ]]; then
                printf '%s %s\n' "$bin" "${AUTO_DNF_APPLY[*]}"
            fi
        fi
    else
        bin="$(command -v emerge 2>/dev/null || true)"
        if [[ -n "$bin" ]]; then
            printf '%s %s\n' "$bin" "${AUTO_EMERGE_SYNC[*]}"
            printf '%s %s\n' "$bin" "${AUTO_EMERGE_PRETEND[*]}"
            if [[ "$mode" == apply ]]; then
                printf '%s %s\n' "$bin" "${AUTO_EMERGE_APPLY[*]}"
            fi
        fi
    fi

    return 0
}

auto_sudo_ok() {
    local mode="$1" line
    local -a words

    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        read -r -a words <<< "$line"
        if ! sudo -n -k -l "${words[@]}" >/dev/null 2>&1; then
            return 1
        fi
    done < <(auto_privileged_commands "$mode")

    return 0
}

auto_install_sudoers() {
    local mode="$1" user line tmp w
    local -a words esc
    local -a rules=()

    user="$(id -un)"

    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        read -r -a words <<< "$line"
        esc=()
        for w in "${words[@]}"; do
            esc+=("$(sudoers_escape "$w")")
        done
        rules+=("${esc[*]}")
    done < <(auto_privileged_commands "$mode")

    if [[ ${#rules[@]} -eq 0 ]]; then
        return 0
    fi

    local joined="" r
    for r in "${rules[@]}"; do
        joined+="${joined:+, }$r"
    done

    tmp="$(mktemp)"
    {
        printf '# Создано linka (linka auto enable). Удаляется командой: linka auto disable\n'
        printf '# Разрешает пользователю %s выполнять БЕЗ пароля только эти точные команды.\n' "$user"
        printf '%s ALL=(root) NOPASSWD: %s\n' "$user" "$joined"
    } > "$tmp"

    if command -v visudo >/dev/null 2>&1 && ! visudo -cf "$tmp" >/dev/null 2>&1; then
        log_error 'Сгенерированный sudoers не прошёл проверку visudo — не устанавливаю.'
        rm -f "$tmp"
        return 1
    fi

    run_root mkdir -p "$(dirname "$AUTO_SUDOERS_FILE")" 2>/dev/null || true

    if ! run_root install -m 0440 -o root -g root "$tmp" "$AUTO_SUDOERS_FILE"; then
        log_error "Не удалось установить $AUTO_SUDOERS_FILE"
        rm -f "$tmp"
        return 1
    fi

    rm -f "$tmp"

    if auto_sudo_ok "$mode"; then
        log_ok "Правило sudoers установлено: $AUTO_SUDOERS_FILE"
    else
        log_warn "Правило записано, но sudo всё ещё просит пароль. Проверьте, что /etc/sudoers подключает /etc/sudoers.d."
        return 1
    fi

    return 0
}

auto_reboot_hint() {
    local out bin
    bin="$(command -v dnf 2>/dev/null || command -v dnf5 2>/dev/null || true)"
    if [[ -z "$bin" ]]; then
        return 1
    fi
    out="$("$bin" needs-restarting -r 2>&1 || true)"
    grep -qi 'reboot is required' <<< "$out"
}

auto_system_fedora() {
    local mode="$1" rc=0 bin

    bin="$(command -v dnf 2>/dev/null || command -v dnf5 2>/dev/null || true)"
    if [[ -z "$bin" ]]; then
        log_warn 'Система: dnf не найден.'
        return 0
    fi

    "$bin" -q --refresh check-update >/dev/null 2>&1 || rc=$?

    case "$rc" in
        0)
            log_info 'Система: обновлений нет.'
            auto_set AUTO_LAST_SYSTEM "$(date +%s)"
            return 0
            ;;
        100)
            ;;
        *)
            log_warn "Система: dnf check-update завершился с кодом $rc."
            return 0
            ;;
    esac

    if [[ "$mode" == notify ]]; then
        log_info 'Система: есть обновления пакетов (режим notify).'
        auto_notify 'Обновления системы' 'Есть обновления пакетов. Применить: sudo dnf upgrade'
        auto_set AUTO_LAST_SYSTEM "$(date +%s)"
        return 0
    fi

    if ! auto_sudo_ok apply; then
        log_warn 'Система: sudo просит пароль. Выполните: linka auto enable --system apply'
        auto_notify 'Обновление системы не выполнено' 'sudo просит пароль: linka auto enable --system apply' critical
        return 0
    fi

    log_info 'Система: dnf upgrade...'
    if run_root "$bin" "${AUTO_DNF_APPLY[@]}"; then
        auto_set AUTO_LAST_SYSTEM "$(date +%s)"
        if auto_reboot_hint; then
            log_ok 'Система обновлена, нужна перезагрузка.'
            auto_notify 'Система обновлена' 'Нужна перезагрузка, чтобы применить обновления ядра/библиотек.'
        else
            log_ok 'Система обновлена.'
            auto_notify 'Система обновлена' 'Пакеты обновлены.'
        fi
    else
        log_warn 'Система: dnf upgrade завершился с ошибкой.'
        auto_notify 'Обновление системы не удалось' "Подробности: $AUTO_LOG" critical
    fi

    return 0
}

auto_system_gentoo() {
    local mode="$1" bin out="" n=0

    bin="$(command -v emerge 2>/dev/null || true)"
    if [[ -z "$bin" ]]; then
        log_warn 'Система: emerge не найден.'
        return 0
    fi

    if ! auto_sudo_ok "$mode"; then
        log_warn "Система: sudo просит пароль. Выполните: linka auto enable --system $mode"
        auto_notify 'Обновление системы не выполнено' "sudo просит пароль: linka auto enable --system $mode" critical
        return 0
    fi

    log_info 'Система: emerge --sync...'
    if ! run_root "$bin" "${AUTO_EMERGE_SYNC[@]}" >/dev/null 2>&1; then
        log_warn 'Система: emerge --sync не удался.'
        return 0
    fi

    out="$(run_root "$bin" "${AUTO_EMERGE_PRETEND[@]}" 2>&1 || true)"
    n="$(printf '%s\n' "$out" | grep -c '^\[ebuild' || true)"

    if [[ "$n" -eq 0 ]]; then
        log_info 'Система: обновлений нет.'
        auto_set AUTO_LAST_SYSTEM "$(date +%s)"
        return 0
    fi

    log_info "Система: пакетов к обновлению — $n."

    if printf '%s\n' "$out" | grep -q '^\[blocks'; then
        log_warn 'Система: emerge сообщает о блокировках — автоматически не обновляю.'
        auto_notify 'Обновления системы' "Пакетов к обновлению: $n, но есть блокировки — нужен ручной emerge." critical
        auto_set AUTO_LAST_SYSTEM "$(date +%s)"
        return 0
    fi

    if [[ "$mode" == notify ]]; then
        auto_notify 'Обновления системы' "Пакетов к обновлению: $n. Применить: emerge -uDN @world"
        auto_set AUTO_LAST_SYSTEM "$(date +%s)"
        return 0
    fi

    log_info 'Система: emerge @world (может занять часы)...'
    if run_root "$bin" "${AUTO_EMERGE_APPLY[@]}"; then
        auto_set AUTO_LAST_SYSTEM "$(date +%s)"
        log_ok 'Система обновлена.'
        auto_notify 'Система обновлена' "Обновлено пакетов: $n. Проверьте etc-update/dispatch-conf."
    else
        log_warn 'Система: emerge завершился с ошибкой.'
        auto_notify 'Обновление системы не удалось' "Подробности: $AUTO_LOG" critical
    fi

    return 0
}

auto_system_step() {
    local mode
    mode="$(auto_get AUTO_SYSTEM off)"

    if [[ "$mode" == off ]]; then
        return 0
    fi

    if ! auto_system_due; then
        log_info 'Система: ещё рано (AUTO_SYSTEM_EVERY_DAYS).'
        return 0
    fi

    if auto_on_battery; then
        log_info 'Система: работаю от батареи — пропускаю.'
        return 0
    fi

    if [[ "$DISTRO" == fedora ]]; then
        auto_system_fedora "$mode"
    else
        auto_system_gentoo "$mode"
    fi

    return 0
}

auto_run_body() {
    local t

    printf '=== %s | linka %s | auto run ===\n' "$(date '+%F %T')" "$LINKA_VERSION"

    for t in git curl; do
        if ! command -v "$t" >/dev/null 2>&1; then
            log_warn "Не найдено: $t — пропускаю."
            return 0
        fi
    done

    if ! auto_network_ok; then
        log_info 'Нет сети — пропускаю.'
        return 0
    fi

    local sm
    sm="$(auto_get AUTO_SHELL apply)"
    if [[ "$sm" != off ]]; then
        auto_shell_step "$sm" || true
    fi

    auto_system_step || true
    return 0
}

auto_run_once() {
    AUTO_MODE=1

    if ! acquire_lock_quiet; then
        log_info 'linka сейчас занята (другой терминал/обновление) — пропускаю.'
        return 0
    fi

    auto_run_body || true
    release_lock
    return 0
}

auto_run_cli() {
    local a verbose=0
    for a in "$@"; do
        case "$a" in
            -v|--verbose) verbose=1 ;;
        esac
    done

    AUTO_MODE=1
    if [[ "$verbose" != 1 ]]; then
        auto_setup_log
    fi

    auto_run_once
    return 0
}

auto_script_path() {
    readlink -f "${BASH_SOURCE[0]:-$0}"
}

auto_have_systemd_user() {
    [[ "$(detect_init_system)" == systemd ]] &&
        command -v systemctl >/dev/null 2>&1 &&
        systemctl --user show-environment >/dev/null 2>&1
}

auto_systemd_install() {
    local script="$1" minutes="$2"

    mkdir -p "$AUTO_UNIT_DIR"

    cat > "$AUTO_UNIT_DIR/linka-auto.service" <<EOF_SVC
[Unit]
Description=linka: фоновое обновление Serpantinum и системы

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash "$script" auto run
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
Nice=15
IOSchedulingClass=idle
TimeoutStartSec=infinity
KillMode=process
EOF_SVC

    cat > "$AUTO_UNIT_DIR/linka-auto.timer" <<EOF_TMR
[Unit]
Description=linka: периодическая проверка обновлений

[Timer]
OnActiveSec=10min
OnUnitActiveSec=${minutes}min
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
EOF_TMR

    systemctl --user daemon-reload || return 1
    systemctl --user enable --now linka-auto.timer || return 1
    return 0
}

auto_systemd_remove() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now linka-auto.timer >/dev/null 2>&1 || true
        systemctl --user stop linka-auto.service >/dev/null 2>&1 || true
    fi

    rm -f "$AUTO_UNIT_DIR/linka-auto.service" "$AUTO_UNIT_DIR/linka-auto.timer"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
    return 0
}

auto_daemon_pid() {
    local pid=""
    if [[ -f "$AUTO_PID_FILE" ]]; then
        pid="$(cat "$AUTO_PID_FILE" 2>/dev/null || true)"
    fi

    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null &&
       grep -q 'daemon' "/proc/$pid/cmdline" 2>/dev/null; then
        printf '%s\n' "$pid"
    fi
    return 0
}

auto_daemon_start() {
    local script="$1"

    if [[ -n "$(auto_daemon_pid)" ]]; then
        return 0
    fi

    if command -v setsid >/dev/null 2>&1; then
        setsid -f bash "$script" auto daemon </dev/null >/dev/null 2>&1 || true
    else
        nohup bash "$script" auto daemon </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
    return 0
}

auto_daemon_stop() {
    local pid
    pid="$(auto_daemon_pid)"
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$AUTO_PID_FILE"
    return 0
}

auto_daemon() {
    local minutes secs

    if command -v flock >/dev/null 2>&1; then
        exec 8>"$AUTO_DAEMON_LOCK" || true
        if ! flock -n 8; then
            return 0
        fi
    fi

    mkdir -p "$STATE_DIR"
    printf '%s\n' "$$" > "$AUTO_PID_FILE"
    trap 'kill "${AUTO_SLEEP_PID:-0}" 2>/dev/null || true; rm -f "$AUTO_PID_FILE"; cleanup_terminal' EXIT

    sleep "${LINKA_AUTO_FIRST_DELAY:-300}" & AUTO_SLEEP_PID=$!
    wait "$AUTO_SLEEP_PID" || true

    while true; do
        ( auto_run_cli ) || true

        minutes="$(auto_get AUTO_INTERVAL_MIN 15)"
        [[ "$minutes" =~ ^[0-9]+$ ]] || minutes=15
        secs=$(( 10#$minutes * 60 ))

        sleep "${LINKA_AUTO_LOOP_SECS:-$secs}" & AUTO_SLEEP_PID=$!
        wait "$AUTO_SLEEP_PID" || true
    done
}

auto_status() {
    local sh sys mins days nt br last
    local script

    sh="$(auto_get AUTO_SHELL apply)"
    sys="$(auto_get AUTO_SYSTEM off)"
    mins="$(auto_get AUTO_INTERVAL_MIN 15)"
    days="$(auto_get AUTO_SYSTEM_EVERY_DAYS 1)"
    nt="$(auto_get AUTO_NOTIFY 1)"
    br="$(auto_get AUTO_BRANCH "$REPO_BRANCH")"
    last="$(auto_get AUTO_LAST_SYSTEM 0)"
    script="$(auto_script_path || true)"

    printf '%sАвтообновление linka%s\n' "$BOLD" "$RESET"

    if auto_have_systemd_user; then
        if systemctl --user is-enabled linka-auto.timer >/dev/null 2>&1; then
            printf '  планировщик:   systemd --user таймер (включён, %s)\n' \
                "$(systemctl --user is-active linka-auto.timer 2>/dev/null || true)"
            systemctl --user list-timers linka-auto.timer --no-pager 2>/dev/null | sed -n '1,2p' | sed 's/^/                 /' || true
        else
            printf '  планировщик:   выключен\n'
        fi
    else
        if [[ -n "$(auto_daemon_pid)" ]]; then
            printf '  планировщик:   демон (pid %s)\n' "$(auto_daemon_pid)"
        elif [[ -f "$AUTO_AUTOSTART_FILE" ]]; then
            printf '  планировщик:   автозапуск настроен, демон сейчас не работает\n'
        else
            printf '  планировщик:   выключен\n'
        fi
    fi

    printf '  Serpantinum:   %s (ветка %s)\n' "$sh" "$br"
    printf '  система:       %s (раз в %s дн.)\n' "$sys" "$days"
    printf '  проверка:      каждые %s мин.\n' "$mins"
    printf '  уведомления:   %s\n' "$([[ "$nt" == 1 ]] && printf да || printf нет)"

    if [[ "$last" =~ ^[0-9]+$ && "$last" -gt 0 ]]; then
        printf '  последнее обновление системы: %s\n' "$(date -d "@$last" '+%F %T' 2>/dev/null || printf '%s' "$last")"
    fi

    if [[ "$sys" != off ]]; then
        if auto_sudo_ok "$sys"; then
            printf '  sudo без пароля: есть\n'
        else
            printf '  sudo без пароля: НЕТ — linka auto enable --system %s\n' "$sys"
        fi
    fi

    if [[ -n "$script" && ! -f "$script" ]]; then
        printf '  ВНИМАНИЕ: файл скрипта не найден: %s\n' "$script"
    fi

    if [[ -f "$AUTO_LOG" ]]; then
        printf '\n  Журнал (%s):\n' "$AUTO_LOG"
        tail -n 6 "$AUTO_LOG" 2>/dev/null | sed 's/^/    /' || true
    fi

    return 0
}

auto_enable() {
    local shell_mode sys_mode minutes days notify branch prev_sys script

    shell_mode="$(auto_get AUTO_SHELL apply)"
    sys_mode="$(auto_get AUTO_SYSTEM off)"
    minutes="$(auto_get AUTO_INTERVAL_MIN 15)"
    days="$(auto_get AUTO_SYSTEM_EVERY_DAYS 1)"
    notify="$(auto_get AUTO_NOTIFY 1)"
    branch="$(auto_get AUTO_BRANCH "$REPO_BRANCH")"
    prev_sys="$sys_mode"

    if [[ -n "${SERPANTINUM_BRANCH:-}" ]]; then
        branch="$SERPANTINUM_BRANCH"
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --shell)      shell_mode="${2:-}"; shift 2 || shift ;;
            --system)     sys_mode="${2:-}"; shift 2 || shift ;;
            --interval)   minutes="${2:-}"; shift 2 || shift ;;
            --every-days) days="${2:-}"; shift 2 || shift ;;
            --branch)     branch="${2:-}"; shift 2 || shift ;;
            --no-notify)  notify=0; shift ;;
            --notify)     notify=1; shift ;;
            *)
                log_error "auto enable: неизвестный параметр: $1"
                usage
                return 1
                ;;
        esac
    done

    if ! auto_valid_mode "$shell_mode"; then
        log_error '--shell: apply | notify | off'
        return 1
    fi
    if ! auto_valid_mode "$sys_mode"; then
        log_error '--system: apply | notify | off'
        return 1
    fi
    if ! auto_valid_uint "$minutes"; then
        log_error '--interval: целое число минут > 0'
        return 1
    fi
    if ! auto_valid_uint "$days"; then
        log_error '--every-days: целое число дней > 0'
        return 1
    fi

    script="$(auto_script_path)"
    if [[ ! -f "$script" || "$script" == /dev/* || "$script" == /proc/* ]]; then
        log_error 'Не могу определить путь к linka: запустите её из файла (не через pipe/process substitution).'
        return 1
    fi
    case "$script" in
        /tmp/*|/var/tmp/*)
            log_warn "linka лежит в $script — временный каталог может очиститься, и автообновление перестанет работать."
            ;;
    esac

    local need_sudo=false
    if [[ -n "$(auto_privileged_commands "$sys_mode")" ]]; then
        need_sudo=true
    fi

    if [[ "$need_sudo" == true ]]; then
        start_sudo_keepalive
        if ! auto_install_sudoers "$sys_mode"; then
            run_optional_root rm -f "$AUTO_SUDOERS_FILE" || true
            log_warn 'Обновление системы отключено (не удалось настроить sudo). Остальное включится.'
            sys_mode=off
        fi
    elif [[ "$prev_sys" != off ]]; then
        start_sudo_keepalive
        run_optional_root rm -f "$AUTO_SUDOERS_FILE" || true
    fi

    auto_set AUTO_SHELL "$shell_mode"
    auto_set AUTO_SYSTEM "$sys_mode"
    auto_set AUTO_INTERVAL_MIN "$minutes"
    auto_set AUTO_SYSTEM_EVERY_DAYS "$days"
    auto_set AUTO_NOTIFY "$notify"
    auto_set AUTO_BRANCH "$branch"

    if auto_have_systemd_user; then
        auto_daemon_stop
        rm -f "$AUTO_AUTOSTART_FILE"
        if auto_systemd_install "$script" "$minutes"; then
            log_ok "Включено: systemd --user таймер linka-auto.timer (каждые ${minutes} мин., первый запуск через ~10 мин)."
        else
            log_error 'Не удалось включить systemd-таймер.'
            return 1
        fi
    else
        auto_systemd_remove
        mkdir -p "$(dirname "$AUTO_AUTOSTART_FILE")"
        cat > "$AUTO_AUTOSTART_FILE" <<EOF_DESK
[Desktop Entry]
Type=Application
Name=linka auto-update
Comment=Фоновое обновление Serpantinum
Exec=bash "$script" auto daemon
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF_DESK
        auto_daemon_stop
        auto_daemon_start "$script"
        log_ok "Включено: фоновый демон (каждые ${minutes} мин.), автозапуск: $AUTO_AUTOSTART_FILE"
        log_info 'Если композитор не читает XDG autostart — добавьте в его конфиг:  exec-once = linka auto daemon'
        log_info 'Для exec-once нужна команда linka в PATH: ln -s "'"$script"'" ~/.local/bin/linka'
    fi

    log_info "Serpantinum: $shell_mode | система: $sys_mode | журнал: $AUTO_LOG"
    return 0
}

auto_disable() {
    local quiet=false prev_sys
    if [[ "${1:-}" == --quiet ]]; then
        quiet=true
    fi

    prev_sys="$(auto_get AUTO_SYSTEM off)"

    auto_systemd_remove
    auto_daemon_stop
    rm -f "$AUTO_AUTOSTART_FILE"

    if [[ "$prev_sys" != off ]]; then
        start_sudo_keepalive
        run_optional_root rm -f "$AUTO_SUDOERS_FILE" || true
    fi

    rm -f "$AUTO_CONF"

    if [[ "$quiet" != true ]]; then
        log_ok 'Автообновление выключено.'
    fi
    return 0
}

auto_menu() {
    local c=''

    clear 2>/dev/null || true
    auto_status
    printf '\n  [e] включить (по умолчанию)   [d] выключить   [Enter] назад: '
    read -rn1 c || true
    printf '\n'

    case "$c" in
        e|E) auto_enable || true ;;
        d|D) auto_disable || true ;;
    esac
    return 0
}

auto_main() {
    local sub="${1:-status}"
    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "$sub" in
        enable)  auto_enable "$@"; end_session ;;
        disable) auto_disable "$@"; end_session ;;
        status)  auto_status ;;
        run)     auto_run_cli "$@" ;;
        daemon)  auto_daemon ;;
        *)
            log_error "auto: неизвестная подкоманда: $sub"
            usage
            exit 1
            ;;
    esac
    return 0
}
