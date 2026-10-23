find_serpantinumd() {
    local cand

    cand="$(command -v serpantinumd 2>/dev/null || true)"
    if [[ -n "$cand" && -x "$cand" ]]; then
        printf '%s\n' "$cand"
        return 0
    fi

    for cand in "$BIN_DIR/serpantinumd" "$TARGET_BASE/bin/serpantinumd"; do
        if [[ -x "$cand" ]]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done

    return 1
}

run_serpantinumd() {
    local bin="$1"
    shift
    env -u SERPANTINUM_DIR -u QS_DIR -u MAIN_QML "$bin" "$@" 9>&- 8>&-
}

shell_running() {
    if pgrep -f "$TARGET_BASE/src/quickshell" >/dev/null 2>&1; then
        return 0
    fi

    if pgrep -f "$GENERATIONS_BASE/.*/src/quickshell" >/dev/null 2>&1; then
        return 0
    fi

    if pgrep -x serpantinumd >/dev/null 2>&1; then
        return 0
    fi

    if pgrep -f "$TARGET_BASE/bin/serpantinumd" >/dev/null 2>&1; then
        return 0
    fi

    if pgrep -f "bin/serpantinumd" >/dev/null 2>&1; then
        return 0
    fi

    if [[ -f "/tmp/serpantinumd.pid" ]]; then
        local p
        p="$(cat /tmp/serpantinumd.pid 2>/dev/null || true)"
        if [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

stop_shell() {
    if ! shell_running; then
        return 0
    fi

    local bin i
    bin="$(find_serpantinumd || true)"

    if [[ -n "$bin" ]]; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 5 env -u SERPANTINUM_DIR -u QS_DIR -u MAIN_QML "$bin" stop >/dev/null 2>&1 || true
        else
            run_serpantinumd "$bin" stop >/dev/null 2>&1 || true
        fi
    fi

    for i in 1 2 3 4 5; do
        if ! shell_running; then
            rm -f "/tmp/serpantinumd.pid" "/tmp/serpantinumd.lock" 2>/dev/null || true
            return 0
        fi
        sleep 1
    done

    pkill -f "$TARGET_BASE/src/quickshell" 2>/dev/null || true
    pkill -f "$GENERATIONS_BASE/.*/src/quickshell" 2>/dev/null || true
    pkill -x serpantinumd 2>/dev/null || true
    pkill -f "$TARGET_BASE/bin/serpantinumd" 2>/dev/null || true
    pkill -f "$BIN_DIR/serpantinumd" 2>/dev/null || true

    for i in 1 2 3; do
        if ! shell_running; then
            rm -f "/tmp/serpantinumd.pid" "/tmp/serpantinumd.lock" 2>/dev/null || true
            return 0
        fi
        sleep 1
    done

    pkill -9 -f "$TARGET_BASE/src/quickshell" 2>/dev/null || true
    pkill -9 -f "$GENERATIONS_BASE/.*/src/quickshell" 2>/dev/null || true
    pkill -9 -x serpantinumd 2>/dev/null || true
    pkill -9 -f "$TARGET_BASE/bin/serpantinumd" 2>/dev/null || true
    pkill -9 -f "$BIN_DIR/serpantinumd" 2>/dev/null || true

    for i in 1 2 3; do
        if ! shell_running; then
            rm -f "/tmp/serpantinumd.pid" "/tmp/serpantinumd.lock" 2>/dev/null || true
            return 0
        fi
        sleep 1
    done

    return 1
}

start_shell() {
    fc-cache -f >/dev/null 2>&1 || true
    export PATH="$BIN_DIR:$PATH"

    if [[ -z "${WAYLAND_DISPLAY:-}" || -z "${XDG_RUNTIME_DIR:-}" ]]; then
        auto_adopt_session_env || true
    fi

    local bin
    bin="$(find_serpantinumd || true)"

    if [[ -z "$bin" ]]; then
        log_warn 'serpantinumd не найден'
        return 1
    fi

    local started=0
    if command -v systemd-run >/dev/null 2>&1 && systemctl --user list-units >/dev/null 2>&1; then
        local env_args=()
        local v
        for v in WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR XDG_CURRENT_DESKTOP XDG_SESSION_TYPE \
                 DESKTOP_SESSION DBUS_SESSION_BUS_ADDRESS HYPRLAND_INSTANCE_SIGNATURE SWAYSOCK \
                 NIRI_SOCKET MANGO_INSTANCE_SIGNATURE QT_QPA_PLATFORM PATH; do
            if [[ -n "${!v:-}" ]]; then
                env_args+=(--setenv="$v=${!v}")
            fi
        done
        if systemd-run --user --collect --slice=app.slice "${env_args[@]}" \
            env -u SERPANTINUM_DIR -u QS_DIR -u MAIN_QML "$bin" start </dev/null >/dev/null 2>&1; then
            started=1
        fi
    fi

    if [[ "$started" -ne 1 ]]; then
        if command -v setsid >/dev/null 2>&1; then
            setsid env -u SERPANTINUM_DIR -u QS_DIR -u MAIN_QML "$bin" start </dev/null >/dev/null 2>&1 9>&- 8>&- &
        else
            nohup env -u SERPANTINUM_DIR -u QS_DIR -u MAIN_QML "$bin" start </dev/null >/dev/null 2>&1 9>&- 8>&- &
        fi
        local d_pid=$!
        disown "$d_pid" 2>/dev/null || true
    fi

    local i
    for i in {1..10}; do
        if shell_running; then
            return 0
        fi
        sleep 0.5
    done

    log_warn "serpantinumd запущен, но статус shell пока не подтверждён ($bin)"
    return 1
}

kill_serpantinum() {
    log_info 'Остановка Serpantinum...'

    stop_shell || true

    pkill -9 -f "$TARGET_BASE/src/quickshell" 2>/dev/null || true
    pkill -9 -x serpantinumd 2>/dev/null || true
    pkill -9 -f "$TARGET_BASE/bin/serpantinumd" 2>/dev/null || true
    pkill -9 -f "$BIN_DIR/serpantinumd" 2>/dev/null || true

    sleep 1

    if shell_running; then
        log_warn 'Часть процессов жива'
        return 1
    fi

    log_ok 'Остановлено.'
    return 0
}

is_sddm_theme_managed() {
    [[ ! -e "$SDDM_THEME_DIR" ]] && return 0
    [[ -f "$SDDM_THEME_DIR/.linka-managed" ]] && return 0
    [[ -f "$SDDM_MANAGED_CONF" ]] && return 0
    return 1
}

is_font_system_managed() {
    [[ -L "$FONT_SYSTEM_DIR" ]] && return 1
    [[ ! -e "$FONT_SYSTEM_DIR" ]] && return 0
    [[ -f "$FONT_SYSTEM_DIR/.linka-managed" ]]
}

install_fonts() {
    local target="$USER_FONT_DIR"
    local cache zip
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-fonts"
    zip="$cache/Iosevka.zip"

    mkdir -p "$target"

    if ! compgen -G "$target/*.ttf" >/dev/null 2>&1; then
        if command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
            log_info 'Шрифты Iosevka (может занять минуту на слабом канале)...'
            mkdir -p "$cache"

            if curl -fL --connect-timeout 15 --retry 3 "$FONT_URL" -o "$zip"; then
                local sha_file="$cache/SHA-256.txt"
                local expected_sha actual_sha
                if curl -fsSL --connect-timeout 10 "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/SHA-256.txt" -o "$sha_file" 2>/dev/null; then
                    expected_sha="$(grep -i 'Iosevka.zip$' "$sha_file" 2>/dev/null | awk '{print $1}' | head -n1)"
                    if [[ -n "$expected_sha" ]] && command -v sha256sum >/dev/null 2>&1; then
                        actual_sha="$(sha256sum "$zip" | awk '{print $1}')"
                        if [[ "$expected_sha" != "$actual_sha" ]]; then
                            log_error "Контрольная сумма шрифтов не совпадает (ожидалась: $expected_sha, получена: $actual_sha). Загрузка отменена."
                            rm -rf "$cache"
                            return 1
                        fi
                        log_info "Контрольная сумма Iosevka.zip проверена ($expected_sha)."
                    fi
                else
                    log_warn 'Не удалось скачать контрольные суммы SHA-256.txt, продолжаю без сверки хеша.'
                fi

                if unzip -qo "$zip" -d "$cache/x"; then
                    find "$cache/x" -type f -iname '*.ttf' ! -iname '*Mono*.ttf' -exec cp -f {} "$target/" \;
                    touch "$target/.linka-managed" 2>/dev/null || true
                else
                    log_warn 'Шрифты: не удалось распаковать'
                fi
            else
                log_warn 'Шрифты: не удалось скачать'
            fi
        else
            log_warn 'Шрифты: нет curl/unzip, пропускаю загрузку'
        fi

        rm -rf "$cache"
    fi

    fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true

    if compgen -G "$target/*.ttf" >/dev/null 2>&1; then
        if [[ -d "$FONT_SYSTEM_DIR" ]] && ! is_font_system_managed; then
            log_warn "Каталог системных шрифтов $FONT_SYSTEM_DIR не управляется linka. Пропускаю установку системных шрифтов."
        else
            run_optional_root mkdir -p "$FONT_SYSTEM_DIR" || true
            run_optional_root cp -f "$target"/*.ttf "$FONT_SYSTEM_DIR/" || true
            run_optional_root touch "$FONT_SYSTEM_DIR/.linka-managed" 2>/dev/null || true
            run_optional_root fc-cache -f /usr/share/fonts >/dev/null 2>&1 || true
        fi
    fi

    return 0
}

setup_services() {
    local is
    is="$(detect_init_system)"

    if [[ "$is" == systemd ]]; then
        run_root systemctl --global enable pipewire wireplumber pipewire-pulse || true
        systemctl --user start pipewire wireplumber pipewire-pulse || true
        if systemctl --user list-unit-files easyeffects.service 2>/dev/null | grep -q -E '^easyeffects\.service([[:space:]]|$)'; then
            systemctl --user enable --now easyeffects.service || true
        fi
        run_root systemctl enable --now NetworkManager.service || true
        if systemctl list-unit-files power-profiles-daemon.service 2>/dev/null | grep -q -E '^power-profiles-daemon\.service([[:space:]]|$)'; then
            run_root systemctl enable --now power-profiles-daemon.service || true
        fi
        if systemctl list-unit-files tuned.service 2>/dev/null | grep -q -E '^tuned\.service([[:space:]]|$)'; then
            run_root systemctl enable --now tuned.service || true
        fi
    elif [[ "$is" == openrc ]]; then
        run_optional_root rc-update add NetworkManager default || true
        run_optional_root rc-service NetworkManager start || true
        if [[ -f /etc/init.d/power-profiles-daemon ]]; then
            run_optional_root rc-update add power-profiles-daemon default || true
            run_optional_root rc-service power-profiles-daemon start || true
        fi
        if [[ -f /etc/init.d/tuned ]]; then
            run_optional_root rc-update add tuned default || true
            run_optional_root rc-service tuned start || true
        fi
    fi

    return 0
}

get_wallpaper_dir() {
    local u=''

    if [[ -f "$HOME/.config/user-dirs.dirs" ]]; then
        u="$(sed -n 's/^XDG_PICTURES_DIR="\(.*\)"/\1/p' "$HOME/.config/user-dirs.dirs" | head -n1)"
        u="${u//\$HOME/$HOME}"
    fi

    if [[ -z "$u" || "$u" == "$HOME" ]] && command -v xdg-user-dir >/dev/null 2>&1; then
        u="$(xdg-user-dir PICTURES 2>/dev/null || true)"
    fi

    if [[ -z "$u" || "$u" == "$HOME" ]]; then
        u="$HOME/Pictures"
    fi

    printf '%s/Wallpapers\n' "${u%/}"
    return 0
}

install_wallpapers() {
    local full="${1:-true}"
    local dir clone src ok=false
    dir="$(get_wallpaper_dir)"
    clone="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-wallpapers"

    mkdir -p "$dir"

    if [[ -d "$clone/.git" ]] &&
       git -C "$clone" fetch --depth 1 origin &&
       git -C "$clone" reset --hard FETCH_HEAD; then
        ok=true
    fi

    if [[ "$ok" != true ]]; then
        rm -rf "$clone"
        if ! git clone --depth 1 "$WALLPAPER_REPO" "$clone"; then
            log_warn 'Обои: клон не удался (сеть)'
            return 0
        fi
    fi

    src="$clone"
    if [[ -d "$clone/images" ]]; then
        src="$clone/images"
    fi

    if [[ ! -d "$src" ]]; then
        return 0
    fi

    local files=() f

    if [[ "$full" == true ]]; then
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find "$src" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \) -print0)
    else
        if command -v shuf >/dev/null 2>&1; then
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$src" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) -print0 | shuf -z -n 3)
        else
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$src" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) -print0 | head -z -n 3)
        fi
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn 'Обои: файлов не найдено'
        return 0
    fi

    for f in "${files[@]}"; do
        cp -f "$f" "$dir/" 2>/dev/null || true
    done

    log_ok "Обои: ${#files[@]} файлов."
    return 0
}

other_display_manager_enabled() {
    local link
    link="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"

    if [[ -n "$link" && "$link" != *sddm* ]]; then
        return 0
    fi

    local dm
    for dm in gdm lightdm greetd lxdm; do
        if systemctl is-active --quiet "$dm.service" 2>/dev/null ||
           systemctl is-enabled --quiet "$dm.service" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

ensure_sddm_package() {
    if [[ "$DISTRO" == fedora ]]; then
        local pkgs=("${SDDM_PKGS[@]}")
        if [[ ${#pkgs[@]} -eq 0 ]]; then
            pkgs=(sddm qt6-qtdeclarative qt6-qtsvg)
        fi
        local missing=()
        local pkg
        for pkg in "${pkgs[@]}"; do
            if ! pkg_installed "$pkg"; then
                missing+=("$pkg")
            fi
        done

        if [[ ${#missing[@]} -eq 0 ]]; then
            return 0
        fi

        run_root dnf install -y "${missing[@]}" || return 1
    else
        local sddm_atoms=(x11-misc/sddm dev-qt/qtdeclarative dev-qt/qtsvg)
        if [[ "$(detect_init_system)" == openrc ]]; then
            sddm_atoms+=(gui-libs/display-manager-init)
        fi

        local missing=()
        for a in "${sddm_atoms[@]}"; do
            if ! pkg_installed "$a"; then
                missing+=("$a")
            fi
        done

        if [[ ${#missing[@]} -eq 0 ]]; then
            return 0
        fi

        run_root emerge --ask=n "${missing[@]}" || return 1
    fi

    return 0
}

setup_sddm() {
    local repo="$1"

    if [[ "$OPT_SDDM" != true ]]; then
        return 0
    fi

    if ! ensure_sddm_package; then
        log_warn 'SDDM: пакет не установлен'
        return 0
    fi

    local src="$repo/config/sddm/themes/material-you"
    if [[ ! -d "$src" ]]; then
        log_warn 'SDDM: тема не найдена в репо'
        return 0
    fi

    if [[ -d "$SDDM_THEME_DIR" ]] && ! is_sddm_theme_managed; then
        log_warn "Каталог темы SDDM $SDDM_THEME_DIR уже существует и не управляется linka (нет метки .linka-managed). Пропускаю установку темы SDDM."
    else
        if ! run_root mkdir -p /etc/sddm.conf.d "$SDDM_THEME_DIR"; then
            log_warn 'SDDM: не удалось создать каталоги'
            return 0
        fi

        if ! run_root cp -a "$src/." "$SDDM_THEME_DIR/"; then
            log_warn 'SDDM: не удалось скопировать тему'
            return 0
        fi

        run_root touch "$SDDM_THEME_DIR/.linka-managed" 2>/dev/null || true
        run_root chmod -R a+rX "$SDDM_THEME_DIR" || true

        if ! run_root tee "$SDDM_MANAGED_CONF" >/dev/null <<'EOF_SDDM'
[Theme]
Current=material-you
ThemeDir=/usr/share/sddm/themes

[General]
InputMethod=
EOF_SDDM
        then
            log_warn 'SDDM: не удалось записать конфиг'
            return 0
        fi
    fi

    if [[ "$(detect_init_system)" == systemd ]]; then
        if other_display_manager_enabled; then
            log_warn 'SDDM: тема установлена, но в системе включён другой display manager — sddm.service не включаю (переключите вручную при желании)'
            return 0
        fi

        if run_root systemctl enable sddm.service; then
            update_state_field SDDM_ENABLED_BY_LINKA true
        else
            log_warn 'SDDM: не удалось включить sddm.service'
            return 0
        fi
    elif [[ "$(detect_init_system)" == openrc ]]; then
        if [[ -f /etc/conf.d/display-manager ]]; then
            run_optional_root sed -i 's/^[#[:space:]]*DISPLAYMANAGER=.*/DISPLAYMANAGER="sddm"/' /etc/conf.d/display-manager 2>/dev/null || true
        else
            printf 'DISPLAYMANAGER="sddm"\n' | run_optional_root tee /etc/conf.d/display-manager >/dev/null || true
        fi

        if run_optional_root rc-update add display-manager default 2>/dev/null || run_optional_root rc-update add sddm default 2>/dev/null; then
            update_state_field SDDM_ENABLED_BY_LINKA true
        else
            log_warn 'SDDM: не удалось добавить display-manager/sddm в rc-update'
        fi
    fi

    log_ok 'SDDM настроен.'
    return 0
}

detect_system_language() {
    local repo="$1"
    local locale="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    local lang="${locale%%[_.@]*}"
    lang="${lang,,}"

    if [[ "$lang" == uk ]]; then lang=ua; fi

    if [[ -n "$lang" && -f "$repo/src/assets/languages/${lang}.json" ]]; then
        printf '%s' "$lang"
    else
        printf 'en'
    fi
    return 0
}

refresh_location() {
    local script="$TARGET_BASE/src/scripts/location.sh"

    if [[ ! -f "$script" ]]; then
        return 0
    fi

    log_info 'Определяю локацию (погода)...'
    if command -v timeout >/dev/null 2>&1; then
        timeout 30 env -u SERPANTINUM_DIR -u QS_DIR -u MAIN_QML bash "$script" --refresh >/dev/null 2>&1 || true
    else
        env -u SERPANTINUM_DIR -u QS_DIR -u MAIN_QML bash "$script" --refresh >/dev/null 2>&1 || true
    fi

    return 0
}
