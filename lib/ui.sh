init_compositor_detection() {
    if [[ ${#SELECTED_COMPOSITORS[@]} -gt 0 ]]; then
        return 0
    fi

    local installed=()
    local c
    local running=''

    for c in hyprland niri sway mango; do
        if is_compositor_installed "$c"; then
            installed+=("$c")
        fi
    done

    local de="${XDG_CURRENT_DESKTOP,,}"
    local se="${DESKTOP_SESSION,,}"

    if [[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]] ||
       pgrep -x mango >/dev/null 2>&1 ||
       [[ "$de" == *mango* || "$se" == *mango* ]]; then
        running=mango
    elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] ||
       pgrep -x Hyprland >/dev/null 2>&1 ||
       pgrep -x hyprland >/dev/null 2>&1 ||
       [[ "$de" == *hyprland* || "$se" == *hyprland* ]]; then
        running=hyprland
    elif [[ -n "${SWAYSOCK:-}" ]] ||
         pgrep -x sway >/dev/null 2>&1 ||
         [[ "$de" == *sway* || "$se" == *sway* ]]; then
        running=sway
    elif pgrep -x niri >/dev/null 2>&1 ||
         [[ "$de" == *niri* || "$se" == *niri* ]]; then
        running=niri
    fi

    SELECTED_COMPOSITORS=()

    if [[ ${#SELECTED_COMPOSITORS_SAVED[@]} -gt 0 ]]; then
        SELECTED_COMPOSITORS=("${SELECTED_COMPOSITORS_SAVED[@]}")
    elif [[ -n "$running" ]]; then
        SELECTED_COMPOSITORS=("$running")
    elif [[ ${#installed[@]} -eq 1 ]]; then
        SELECTED_COMPOSITORS=("${installed[0]}")
    fi

    return 0
}

selected_compositors_string() {
    if [[ ${#SELECTED_COMPOSITORS[@]} -gt 0 ]]; then
        printf '%s' "${SELECTED_COMPOSITORS[*]}"
    fi
    return 0
}

read_key() {
    local k='' r=''

    IFS= read -rsn1 k 2>/dev/null || true

    if [[ "$k" == $'\x1b' ]]; then
        IFS= read -rsn2 -t 0.05 r 2>/dev/null || true

        case "$r" in
            '[A'|'OA') printf 'UP\n' ;;
            '[B'|'OB') printf 'DOWN\n' ;;
            *) printf 'ESC\n' ;;
        esac

        return 0
    fi

    if [[ -z "$k" || "$k" == $'\n' || "$k" == $'\r' ]]; then
        printf 'ENTER\n'
        return 0
    fi

    if [[ "$k" == ' ' ]]; then
        printf 'SPACE\n'
        return 0
    fi

    printf '%s\n' "$k"
    return 0
}

toggle_compositor() {
    local t="$1"
    local c
    local f=false
    local u=()

    if [[ ${#SELECTED_COMPOSITORS[@]} -gt 0 ]]; then
        for c in "${SELECTED_COMPOSITORS[@]}"; do
            if [[ "$c" == "$t" ]]; then
                f=true
            else
                u+=("$c")
            fi
        done
    fi

    if [[ "$f" == false ]]; then
        u+=("$t")
    fi

    if [[ ${#u[@]} -eq 0 ]]; then
        SELECTED_COMPOSITORS=()
    else
        SELECTED_COMPOSITORS=("${u[@]}")
    fi

    return 0
}

draw_banner() {
    clear 2>/dev/null || true
    printf "%s%s" "$BOLD" "$C_CYAN"
    cat << "EOF"
██╗       ██╗    ███╗   ██╗    ██╗  ██╗     █████╗
██║       ██║    ████╗  ██║    ██║ ██╔╝    ██╔══██╗
██║       ██║    ██╔██╗ ██║    █████╔╝     ███████║
██║       ██║    ██║╚██╗██║    ██╔═██╗     ██╔══██║
███████╗  ██║    ██║ ╚████║    ██║  ██╗    ██║  ██║
╚══════╝  ╚═╝    ╚═╝  ╚═══╝    ╚═╝  ╚═╝    ╚═╝  ╚═╝
EOF
    printf "%s\n" "$RESET"

    local LINKA_GH="https://github.com/Tkanchik/linka"

    local OSC8_GH=$'\e]8;;'"${LINKA_GH}"$'\a'
    local OSC8_TW=$'\e]8;;https://twitter.com/ilyamirox\a'
    local OSC8_RD=$'\e]8;;https://reddit.com/u/ilyamiro1\a'
    local OSC8_TG=$'\e]8;;https://t.me/serpantinum_git\a'
    local OSC8_KF=$'\e]8;;https://ko-fi.com/ilyamiro\a'
    local OSC8_END=$'\e]8;;\a'

    local user_name="${USER:-$(whoami)}"
    local os_name
    os_name="$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | sed "s/[\x27\"]//g")"
    [[ -z "$os_name" ]] && os_name="${DISTRO:-Linux}"

    local cpu_info
    cpu_info="$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
    [[ -z "$cpu_info" ]] && cpu_info="Unknown CPU"

    local gpu_info
    gpu_info="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | sed -E 's/^[0-9a-f:.]+ [^:]+: //; s/ \(rev [0-9a-f]+\)//' | head -n 1 | xargs)"
    [[ -z "$gpu_info" ]] && gpu_info="Unknown GPU"

    local target_ver="${TARGET_VERSION:-}"
    if [[ -z "$target_ver" ]]; then
        target_ver="$(get_installed_version 2>/dev/null || echo "2.2.4")"
    fi
    local target_commit="${SHELL_COMMIT:-}"
    if [[ -z "$target_commit" ]]; then
        target_commit="$(get_installed_commit 2>/dev/null || echo "unknown")"
    fi
    local short_commit="${target_commit:0:7}"
    local install_mode
    install_mode="$(detect_install_state 2>/dev/null || echo "current")"

    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%s%-12s%s %s%s%s\n" "$BOLD" "GitHub:" "$RESET" "$OSC8_GH" "$LINKA_GH" "$OSC8_END"
    printf "\033[K%s%-12s%s %s@ilyamirox%s  |  %s%sReddit:%s %su/ilyamiro1%s\n" "$BOLD" "Twitter:" "$RESET" "$OSC8_TW" "$OSC8_END" "$BOLD" "$C_RED" "$RESET" "$OSC8_RD" "$OSC8_END"
    printf "\033[K%s%-12s%s %shttps://t.me/serpantinum_git%s\n" "$BOLD" "Telegram:" "$RESET" "$OSC8_TG" "$OSC8_END"
    printf "\033[K%s%-12s%s %shttps://ko-fi.com/ilyamiro (Поддержите проект!)%s\n" "$BOLD" "Поддержать:" "$RESET" "$OSC8_KF" "$OSC8_END"
    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%sПользователь:%s %-25s | %sОС:%s %s\n" "$BOLD" "$RESET" "$user_name" "$BOLD" "$RESET" "$os_name"
    printf "\033[K%sЦП:%s %-35s | %sГП:%s %s\n" "$BOLD" "$RESET" "$cpu_info" "$BOLD" "$RESET" "$gpu_info"
    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%sЦелевая версия:%s %-10s (%-7s) | %sРежим установки:%s %s\n" "$BOLD" "$RESET" "$target_ver" "$short_commit" "$BOLD" "$RESET" "$install_mode"
    printf "\033[K[d] Диагностика   [r] Откат\n"
    printf "\033[K%s================================================================================%s\n\n" "$C_BLUE" "$RESET"
}

show_package_overview() {
    local target_list=("${REQUIRED_PKGS[@]}")
    for comp in "${SELECTED_COMPOSITORS[@]}"; do
        target_list+=("$(comp_atom "$comp")")
    done
    if [[ "$OPT_SDDM" == true ]]; then
        target_list+=("${SDDM_PKGS[@]}")
    fi

    if [[ "$DISTRO" == "gentoo" ]]; then
        local filtered=()
        mapfile -t filtered < <(gentoo_filter_atoms "${target_list[@]}")
        if [[ ${#filtered[@]} -gt 0 && -n "${filtered[0]}" ]]; then
            target_list=("${filtered[@]}")
        fi
    fi

    local overview_items=()
    for pkg in "${target_list[@]}"; do
        if pkg_installed "$pkg"; then
            overview_items+=("$(printf '%s[✓] %s (установлен)%s' "$C_GREEN" "$pkg" "$RESET")")
        else
            overview_items+=("$(printf '%s[✗] %s (отсутствует)%s' "$C_RED" "$pkg" "$RESET")")
        fi
    done

    printf "\e[?25h" 2>/dev/null || true
    stty echo icanon 2>/dev/null || true

    if command -v fzf &>/dev/null; then
        printf "%s\n" "${overview_items[@]}" | fzf \
            --ansi \
            --border=rounded \
            --margin=1,2 \
            --height=25 \
            --prompt="Пакет > " \
            --header="Обзор пакетов Serpantinum (Esc/Enter для возврата)" >/dev/null || true
    else
        printf '\n%s=== Обзор пакетов ===%s\n' "$BOLD" "$RESET"
        printf '%s\n' "${overview_items[@]}"
        printf '\n'
        read -rp "Нажмите Enter для возврата в меню..." _ || true
    fi

    stty -echo icanon 2>/dev/null || true
    printf "\e[?25l" 2>/dev/null || true
}

auto_is_enabled() {
    if auto_have_systemd_user; then
        systemctl --user is-enabled linka-auto.timer >/dev/null 2>&1
    else
        [[ -n "$(auto_daemon_pid 2>/dev/null || true)" || -f "${AUTO_AUTOSTART_FILE:-}" ]]
    fi
}

draw_menu() {
    local title="$1"
    shift

    local cursor="$1"
    shift

    local items=("$@")
    local i

    clear 2>/dev/null || true

    printf '%s%s%s | linka %s%s\n\n' "$BOLD" "$C_CYAN" "$title" "$LINKA_VERSION" "$RESET"

    for i in "${!items[@]}"; do
        if [[ "$i" -eq "$cursor" ]]; then
            printf '%s%s ▸ %s%s\n' "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
        else
            printf '    %s\n' "${items[$i]}"
        fi
    done

    return 0
}

manage_compositors_menu() {
    if [[ ! -t 0 ]]; then
        return 0
    fi

    local cursor=0
    local k
    local m_hypr m_niri m_sway m_mango
    local sel
    local st_hypr="не установлен" st_niri="не установлен" st_sway="не установлен" st_mango="не установлен"

    if is_compositor_installed hyprland; then
        st_hypr="установлен"
    fi
    if is_compositor_installed niri; then
        st_niri="установлен"
    fi
    if is_compositor_installed sway; then
        st_sway="установлен"
    fi
    if is_compositor_installed mango; then
        st_mango="установлен"
    fi

    local rendered_lines=0

    while true; do
        draw_banner
        printf "%s%sЦелевой композитор (niri, hyprland, sway, mango):%s\n\n" "$BOLD" "$C_CYAN" "$RESET"
        rendered_lines=0

        while true; do
            m_hypr="[ ]"
            m_niri="[ ]"
            m_sway="[ ]"
            m_mango="[ ]"

            sel="$(selected_compositors_string)"

            if [[ " ${sel:-} " == *" hyprland "* ]]; then m_hypr="${C_GREEN}[✓]${RESET}"; fi
            if [[ " ${sel:-} " == *" niri "* ]]; then m_niri="${C_GREEN}[✓]${RESET}"; fi
            if [[ " ${sel:-} " == *" sway "* ]]; then m_sway="${C_GREEN}[✓]${RESET}"; fi
            if [[ " ${sel:-} " == *" mango "* ]]; then m_mango="${C_GREEN}[✓]${RESET}"; fi

            local items=(
                "1. $m_niri Niri (${st_niri})"
                "2. $m_hypr Hyprland (${st_hypr})"
                "3. $m_sway Sway (${st_sway})"
                "4. $m_mango Mango (${st_mango})"
                "5. ${BOLD}Готово (назад)${RESET}"
            )

            if [[ "$rendered_lines" -gt 0 ]]; then
                printf "\033[%dA" "$rendered_lines"
            fi

            for i in "${!items[@]}"; do
                if [[ "$i" -eq "$cursor" ]]; then
                    printf "\r\033[K  %s%s>%s %s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
                else
                    printf "\r\033[K    %s\n" "${items[$i]}"
                fi
            done
            rendered_lines=${#items[@]}

            k="$(read_key)"

            case "$k" in
                UP|[kK])
                    if [[ "$cursor" -gt 0 ]]; then cursor=$((cursor-1)); else cursor=4; fi ;;
                DOWN|[jJ])
                    if [[ "$cursor" -lt 4 ]]; then cursor=$((cursor+1)); else cursor=0; fi ;;
                "1") toggle_compositor niri ;;
                "2") toggle_compositor hyprland ;;
                "3") toggle_compositor sway ;;
                "4") toggle_compositor mango ;;
                "5"|ESC|[qQ]) return 0 ;;
                ENTER|SPACE)
                    case "$cursor" in
                        0) toggle_compositor niri ;;
                        1) toggle_compositor hyprland ;;
                        2) toggle_compositor sway ;;
                        3) toggle_compositor mango ;;
                        4) return 0 ;;
                    esac
                    ;;
            esac
        done
    done
}

run_installer_ui() {
    if [[ "${SKIP_INSTALLER_UI:-false}" == true ]]; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        if [[ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]]; then
            log_error 'Нет TTY и не выбран compositor.'
            return 1
        fi
        return 0
    fi

    local cursor=0
    local k
    local comps
    local sel

    if [[ ${#SELECTED_COMPOSITORS[@]} -gt 0 ]]; then
        cursor=3
    fi

    local rendered_lines=0

    while true; do
        draw_banner
        rendered_lines=0

        while true; do
            sel="$(selected_compositors_string)"
            comps="${sel:-не выбран}"

            local s_sddm="${DIM}[OFF]${RESET}"
            local s_wp="${DIM}[3 Random]${RESET}"
            [[ "$OPT_SDDM" == true ]] && s_sddm="${C_GREEN}[ON]${RESET}"
            [[ "$INSTALL_FULL_WALLPAPERS" == true ]] && s_wp="${C_GREEN}[Full Pack]${RESET}"

            local items=(
                "1. Целевой композитор (${C_GREEN}${comps}${RESET})"
                "2. Дисплейный менеджер SDDM ${s_sddm}"
                "3. Набор обоев ${s_wp}"
                "4. ${BOLD}${C_GREEN}НАЧАТЬ УСТАНОВКУ${RESET}"
                "5. ${DIM}Отмена${RESET}"
            )

            if [[ "$rendered_lines" -gt 0 ]]; then
                printf "\033[%dA" "$rendered_lines"
            fi

            for i in "${!items[@]}"; do
                if [[ "$i" -eq "$cursor" ]]; then
                    printf "\r\033[K  %s%s>%s %s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
                else
                    printf "\r\033[K    %s\n" "${items[$i]}"
                fi
            done
            rendered_lines=${#items[@]}

            k="$(read_key)"

            case "$k" in
                UP|[kK])
                    if [[ "$cursor" -gt 0 ]]; then cursor=$((cursor-1)); else cursor=$(( ${#items[@]} - 1 )); fi ;;
                DOWN|[jJ])
                    if [[ "$cursor" -lt $(( ${#items[@]} - 1 )) ]]; then cursor=$((cursor+1)); else cursor=0; fi ;;
                "1") manage_compositors_menu; break ;;
                "2")
                    if [[ "$OPT_SDDM" == true ]]; then OPT_SDDM=false; else OPT_SDDM=true; fi ;;
                "3")
                    if [[ "$INSTALL_FULL_WALLPAPERS" == true ]]; then INSTALL_FULL_WALLPAPERS=false; else INSTALL_FULL_WALLPAPERS=true; fi ;;
                "4")
                    if [[ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]]; then
                        log_error 'Выберите compositor'
                        sleep 1
                        continue
                    fi
                    return 0
                    ;;
                "5"|ESC|[qQ])
                    return 1
                    ;;
                ENTER|SPACE)
                    case "$cursor" in
                        0) manage_compositors_menu; break ;;
                        1) if [[ "$OPT_SDDM" == true ]]; then OPT_SDDM=false; else OPT_SDDM=true; fi ;;
                        2) if [[ "$INSTALL_FULL_WALLPAPERS" == true ]]; then INSTALL_FULL_WALLPAPERS=false; else INSTALL_FULL_WALLPAPERS=true; fi ;;
                        3)
                            if [[ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]]; then
                                log_error 'Выберите compositor'
                                sleep 1
                                continue
                            fi
                            return 0
                            ;;
                        4) return 1 ;;
                    esac
                    ;;
            esac
        done
    done
}

usage() {
    cat <<EOF_USAGE
linka ${LINKA_VERSION} — Serpantinum installer (Fedora/Gentoo)

  linka                       меню
  linka install               установка (поверх существующей — без затирания конфигов)
  linka reinstall             чистая переустановка (конфиги бэкапятся)
  linka update                обновление
  linka update --force        принудительное обновление поверх текущего коммита
  linka rollback              откат файлов оболочки и настроек (без пакетов ОС)
  linka doctor                диагностика без изменений
  linka update --dry-run       план действий без изменений (также install, reinstall, remove, rollback)
  linka remove                удаление
  linka kill                  остановка

Фоновое автообновление:
  linka auto enable [опции]   включить (таймер systemd --user или демон)
  linka auto disable          выключить
  linka auto status           состояние и последние строки журнала
  linka auto run [-v]         один проход (его вызывает таймер); -v — вывод на экран
  linka auto daemon           цикл в фоне (для систем без systemd --user)

  Опции auto enable:
    --shell apply|notify|off  Serpantinum: обновлять сам / только уведомлять / не трогать (apply)
    --system off|notify|apply пакеты ОС (dnf / emerge): не трогать / уведомлять / обновлять (off)
    --interval МИНУТЫ         как часто проверять (15)
    --every-days ДНИ          как часто трогать пакеты ОС (1)
    --no-notify               без уведомлений

Переменные окружения:
  SERPANTINUM_BRANCH=master   ветка репозитория (по умолчанию master)
  SERPANTINUM_FORCE_UPDATE=1  то же, что update --force
  SERPANTINUM_MATUGEN_COMPAT=0  отключить автоправку совместимости с matugen
  LINKA_BACKUP_KEEP=5         сколько последних бэкапов хранить (0 — не удалять)
EOF_USAGE
}

linka_main_menu() {
    if [[ ! -t 0 ]]; then
        log_warn 'Нет интерактивного TTY.'
        usage
        return 0
    fi

    load_state
    init_compositor_detection
    OLD_VERSION="$(get_installed_version 2>/dev/null || echo "2.2.4")"
    TARGET_VERSION="$(get_target_version "$CACHE_BASE" 2>/dev/null || echo "$OLD_VERSION")"
    TARGET_COMMIT="$(get_installed_commit 2>/dev/null || echo "unknown")"
    INSTALL_STATE="$(detect_install_state)"


    local cursor=0
    if [[ "$INSTALL_STATE" == "current" ]]; then
        cursor=5
    fi

    stty -echo icanon 2>/dev/null || true
    printf "\e[?25l" 2>/dev/null || true

    while true; do
        draw_banner
        local rendered_lines=0

        while true; do
            local comp_str
            comp_str="$(selected_compositors_string)"
            local comp_item
            if [[ -z "$comp_str" ]]; then
                comp_item="${C_RED}(не выбран)${RESET}"
            else
                comp_item="${C_GREEN}(${comp_str})${RESET}"
            fi

            local s_sddm="${DIM}[OFF]${RESET}"
            local s_wp="${DIM}[3 Random]${RESET}"
            local s_auto="${DIM}[OFF]${RESET}"

            [[ "$OPT_SDDM" == true ]] && s_sddm="${C_GREEN}[ON]${RESET}"
            [[ "$INSTALL_FULL_WALLPAPERS" == true ]] && s_wp="${C_GREEN}[Full Pack]${RESET}"
            if auto_is_enabled 2>/dev/null; then
                s_auto="${C_GREEN}[ON]${RESET}"
            fi

            local pkg_count="${#REQUIRED_PKGS[@]}"

            local items=()
            items+=("1. Обзор установки пакетов ($pkg_count основных пакетов)")
            items+=("2. Целевой композитор $comp_item")
            items+=("3. Дисплейный менеджер SDDM $s_sddm")
            items+=("4. Набор обоев $s_wp")
            items+=("5. Фоновое автообновление $s_auto")

            if [[ "$INSTALL_STATE" == "current" ]]; then
                items+=("6. ${BOLD}${C_GREEN}Обновить${RESET}")
                items+=("7. ${BOLD}${C_YELLOW}Переустановить${RESET}")
                items+=("8. ${DIM}Выход${RESET}")
            else
                items+=("6. ${BOLD}${C_GREEN}Установить${RESET}")
                items+=("7. ${DIM}Выход${RESET}")
            fi

            if [[ "$rendered_lines" -gt 0 ]]; then
                printf "\033[%dA" "$rendered_lines"
            fi

            for i in "${!items[@]}"; do
                if [[ "$i" -eq "$cursor" ]]; then
                    printf "\r\033[K  %s%s>%s %s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
                else
                    printf "\r\033[K    %s\n" "${items[$i]}"
                fi
            done
            rendered_lines=${#items[@]}

            local k
            k="$(read_key)"

            case "$k" in
                UP|[kK])
                    if [[ "$cursor" -gt 0 ]]; then
                        cursor=$((cursor - 1))
                    else
                        cursor=$(( ${#items[@]} - 1 ))
                    fi
                    ;;
                DOWN|[jJ])
                    if [[ "$cursor" -lt $(( ${#items[@]} - 1 )) ]]; then
                        cursor=$((cursor + 1))
                    else
                        cursor=0
                    fi
                    ;;
                "1")
                    show_package_overview
                    break
                    ;;
                "2")
                    manage_compositors_menu
                    break
                    ;;
                "3")
                    if [[ "$OPT_SDDM" == true ]]; then OPT_SDDM=false; else OPT_SDDM=true; fi
                    ;;
                "4")
                    if [[ "$INSTALL_FULL_WALLPAPERS" == true ]]; then INSTALL_FULL_WALLPAPERS=false; else INSTALL_FULL_WALLPAPERS=true; fi
                    ;;
                "5")
                    cleanup_terminal
                    auto_menu
                    stty -echo icanon 2>/dev/null || true
                    printf "\e[?25l" 2>/dev/null || true
                    break
                    ;;
                "6")
                    cleanup_terminal
                    SKIP_INSTALLER_UI=true
                    if [[ "$INSTALL_STATE" == "current" ]]; then
                        FORCE_UPDATE=0
                        prepare_environment
                        linka_run_reported update flow_update || true
                    else
                        FORCE_UPDATE=0
                        prepare_environment
                        linka_run_reported install flow_install install || true
                    fi
                    SKIP_INSTALLER_UI=false
                    end_session
                    read -r -p 'Нажмите Enter для продолжения...' _ || true
                    stty -echo icanon 2>/dev/null || true
                    printf "\e[?25l" 2>/dev/null || true
                    break
                    ;;
                "7")
                    if [[ "$INSTALL_STATE" == "current" ]]; then
                        cleanup_terminal
                        SKIP_INSTALLER_UI=true
                        FORCE_UPDATE=0
                        prepare_environment
                        linka_run_reported reinstall flow_install reinstall || true
                        SKIP_INSTALLER_UI=false
                        end_session
                        read -r -p 'Нажмите Enter для продолжения...' _ || true
                        stty -echo icanon 2>/dev/null || true
                        printf "\e[?25l" 2>/dev/null || true
                        break
                    else
                        cleanup_terminal
                        return 0
                    fi
                    ;;
                "8")
                    if [[ "$INSTALL_STATE" == "current" ]]; then
                        cleanup_terminal
                        return 0
                    fi
                    ;;
                ENTER|SPACE)
                    case "$cursor" in
                        0)
                            show_package_overview
                            break
                            ;;
                        1)
                            manage_compositors_menu
                            break
                            ;;
                        2)
                            if [[ "$OPT_SDDM" == true ]]; then OPT_SDDM=false; else OPT_SDDM=true; fi
                            ;;
                        3)
                            if [[ "$INSTALL_FULL_WALLPAPERS" == true ]]; then INSTALL_FULL_WALLPAPERS=false; else INSTALL_FULL_WALLPAPERS=true; fi
                            ;;
                        4)
                            cleanup_terminal
                            auto_menu
                            stty -echo icanon 2>/dev/null || true
                            printf "\e[?25l" 2>/dev/null || true
                            break
                            ;;
                        5)
                            cleanup_terminal
                            SKIP_INSTALLER_UI=true
                            if [[ "$INSTALL_STATE" == "current" ]]; then
                                FORCE_UPDATE=0
                                prepare_environment
                                linka_run_reported update flow_update || true
                            else
                                FORCE_UPDATE=0
                                prepare_environment
                                linka_run_reported install flow_install install || true
                            fi
                            SKIP_INSTALLER_UI=false
                            end_session
                            read -r -p 'Нажмите Enter для продолжения...' _ || true
                            stty -echo icanon 2>/dev/null || true
                            printf "\e[?25l" 2>/dev/null || true
                            break
                            ;;
                        6)
                            if [[ "$INSTALL_STATE" == "current" ]]; then
                                cleanup_terminal
                                SKIP_INSTALLER_UI=true
                                FORCE_UPDATE=0
                                prepare_environment
                                linka_run_reported reinstall flow_install reinstall || true
                                SKIP_INSTALLER_UI=false
                                end_session
                                read -r -p 'Нажмите Enter для продолжения...' _ || true
                                stty -echo icanon 2>/dev/null || true
                                printf "\e[?25l" 2>/dev/null || true
                                break
                            else
                                cleanup_terminal
                                return 0
                            fi
                            ;;
                        7)
                            cleanup_terminal
                            return 0
                            ;;
                    esac
                    ;;
                [sS]|kill)
                    cleanup_terminal
                    read -r -p 'Остановить Quickshell? [y/N] ' confirm_stop || true
                    if [[ "$confirm_stop" =~ ^[Yy]$ ]]; then
                        kill_serpantinum || true
                        end_session
                        read -r -p 'Нажмите Enter для продолжения...' _ || true
                    fi
                    stty -echo icanon 2>/dev/null || true
                    printf "\e[?25l" 2>/dev/null || true
                    break
                    ;;
                [dD])
                    cleanup_terminal
                    linka_doctor || true
                    read -r -p 'Нажмите Enter для продолжения...' _ || true
                    stty -echo icanon 2>/dev/null || true
                    printf "\e[?25l" 2>/dev/null || true
                    break
                    ;;
                [rR])
                    cleanup_terminal
                    read -r -p 'Откатить файлы оболочки и настройки? [y/N] ' confirm_rollback || true
                    if [[ "$confirm_rollback" =~ ^[Yy]$ ]]; then
                        acquire_lock
                        linka_recover_transaction && linka_run_reported rollback linka_rollback || true
                        end_session
                    fi
                    read -r -p 'Нажмите Enter для продолжения...' _ || true
                    stty -echo icanon 2>/dev/null || true
                    printf "\e[?25l" 2>/dev/null || true
                    break
                    ;;
                ESC|[qQ])
                    cleanup_terminal
                    return 0
                    ;;
            esac
        done
    done
}
