detect_distro_backend() {
    local osr="${LINKA_OS_RELEASE:-/etc/os-release}" id="" like=""

    if [[ ! -r "$osr" ]]; then
        return 0
    fi

    id="$( (. "$osr" >/dev/null 2>&1; printf '%s' "${ID:-}") || true)"
    like="$( (. "$osr" >/dev/null 2>&1; printf '%s' "${ID_LIKE:-}") || true)"

    case "$id" in
        fedora|gentoo)
            printf '%s\n' "$id"
            return 0
            ;;
    esac

    case " $like " in
        *' fedora '*)
            printf 'fedora\n'
            return 0
            ;;
        *' gentoo '*)
            printf 'gentoo\n'
            return 0
            ;;
    esac

    return 0
}

init_package_lists() {
    if [[ "$DISTRO" == 'fedora' ]]; then
        REQUIRED_PKGS=(
            kitty cava zbar pavucontrol alsa-utils wl-clipboard fd-find ripgrep
            jq socat inotify-tools pamixer brightnessctl ddcutil acpi iw
            bluez libnotify NetworkManager lm_sensors bc pipewire wireplumber
            pipewire-pulseaudio pipewire-alsa pulseaudio-libs python3 ImageMagick
            wget file git psmisc ffmpeg-free fastfetch unzip python3-websockets
            qt6-qtwebsockets qt6-qtmultimedia qt6-qt5compat grim playerctl
            xdg-desktop-portal-gtk slurp wmctrl easyeffects nautilus qt5-qtwayland
            qt5-qtquickcontrols qt5-qtquickcontrols2 qt6-qtwayland qt5ct qt6ct
            wf-recorder adw-gtk3-theme
            qt6-qtdeclarative qt6-qtsvg qt6-qtshadertools quickshell
        )
        SDDM_PKGS=(sddm qt6-qtdeclarative qt6-qtsvg)
        OPTIONAL_PKGS=(matugen satty wl-gammarelay-rs cliphist)
        CORE_PKGS=(quickshell qt6-qtdeclarative qt6-qtmultimedia pipewire wireplumber)
        BOOTSTRAP_TOOLS=(jq curl git unzip fc-list)
        BOOTSTRAP_PKGS=(jq curl git unzip fontconfig)
    else
        REQUIRED_PKGS=(
            dev-vcs/git media-gfx/zbar media-sound/pavucontrol media-sound/alsa-utils
            gui-apps/wl-clipboard sys-apps/fd sys-apps/ripgrep
            app-misc/cliphist
            app-misc/jq net-misc/socat sys-fs/inotify-tools media-sound/pamixer
            app-misc/brightnessctl app-misc/ddcutil sys-power/acpi net-wireless/iw
            net-wireless/bluez x11-libs/libnotify net-misc/networkmanager
            sys-apps/lm-sensors sys-devel/bc media-video/pipewire media-video/wireplumber
            media-libs/libpulse dev-lang/python media-gfx/imagemagick net-misc/wget
            sys-apps/file sys-process/psmisc media-video/ffmpeg app-misc/fastfetch
            app-arch/unzip dev-python/websockets dev-qt/qtwebsockets dev-qt/qtmultimedia
            dev-qt/qt5compat gui-apps/grim media-sound/playerctl
            sys-apps/xdg-desktop-portal-gtk
            gui-apps/slurp x11-misc/wmctrl
            media-sound/easyeffects gnome-base/nautilus dev-qt/qtwayland
            gui-apps/qt6ct
            dev-qt/qtdeclarative dev-qt/qtsvg dev-qt/qtshadertools
            gui-apps/wf-recorder x11-themes/adw-gtk3 media-video/gpu-screen-recorder
            x11-terms/kitty media-sound/cava gui-apps/quickshell
            x11-misc/matugen
            gui-apps/satty
            sys-power/power-profiles-daemon
        )
        SDDM_PKGS=(x11-misc/sddm dev-qt/qtdeclarative dev-qt/qtsvg)
        OPTIONAL_PKGS=(gui-apps/wl-gammarelay-rs)
        CORE_PKGS=(gui-apps/quickshell dev-qt/qtdeclarative dev-qt/qtmultimedia media-video/pipewire media-video/wireplumber)
        BOOTSTRAP_TOOLS=(jq curl git unzip fc-list)
        BOOTSTRAP_PKGS=(app-misc/jq net-misc/curl dev-vcs/git app-arch/unzip media-libs/fontconfig)
    fi

    return 0
}

preflight() {
    DISTRO="$(detect_distro_backend)"
    if [[ -z "$DISTRO" ]]; then
        log_error 'Только Fedora и Gentoo.'
        exit 1
    fi

    require_not_root
    init_package_lists
    return 0
}

pkg_installed() {
    local pkg="$1"

    if [[ "$DISTRO" == 'fedora' ]]; then
        if rpm -q "$pkg" >/dev/null 2>&1; then
            return 0
        fi
        if rpm -q --whatprovides "$pkg" >/dev/null 2>&1; then
            return 0
        fi
        if command -v "$pkg" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    if [[ -d /var/db/pkg ]]; then
        local clean="${pkg#[><=~]}"
        clean="${clean%%:*}"
        clean="${clean%%-[0-9]*}"
        if compgen -G "/var/db/pkg/${clean}-[0-9]*" >/dev/null 2>&1; then
            return 0
        fi
    fi

    if command -v portageq >/dev/null 2>&1; then
        if portageq has_version / "$pkg" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    if command -v qlist >/dev/null 2>&1; then
        if qlist -I "$pkg" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    return 2
}

comp_atom() {
    local c="${1,,}"
    if [[ "$DISTRO" == 'fedora' ]]; then
        case "$c" in
            hyprland) printf 'hyprland\n' ;;
            niri)     printf 'niri\n' ;;
            sway)     printf 'sway\n' ;;
            mango)    printf 'mangowm\n' ;;
            *)        printf '%s\n' "$1" ;;
        esac
        return 0
    fi

    case "$c" in
        hyprland) printf 'gui-wm/hyprland\n' ;;
        niri)     printf 'gui-wm/niri\n' ;;
        sway)     printf 'gui-wm/sway\n' ;;
        mango)    printf 'gui-wm/mangowm\n' ;;
        *)        printf '%s\n' "$1" ;;
    esac
}

is_compositor_installed() {
    local comp="${1,,}"
    case "$comp" in
        hyprland)
            command -v hyprland >/dev/null 2>&1 ||
            command -v Hyprland >/dev/null 2>&1 ||
            pkg_installed "$(comp_atom hyprland)" 2>/dev/null
            ;;
        niri)
            command -v niri >/dev/null 2>&1 ||
            pkg_installed "$(comp_atom niri)" 2>/dev/null
            ;;
        sway)
            command -v sway >/dev/null 2>&1 ||
            pkg_installed "$(comp_atom sway)" 2>/dev/null
            ;;
        mango)
            command -v mango >/dev/null 2>&1 ||
            pkg_installed "$(comp_atom mango)" 2>/dev/null
            ;;
        *)
            command -v "$comp" >/dev/null 2>&1 ||
            pkg_installed "$(comp_atom "$comp")" 2>/dev/null
            ;;
    esac
}

bootstrap_installer_deps() {
    local missing=()
    local i

    for i in "${!BOOTSTRAP_TOOLS[@]}"; do
        if ! command -v "${BOOTSTRAP_TOOLS[$i]}" >/dev/null 2>&1; then
            missing+=("${BOOTSTRAP_PKGS[$i]}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Bootstrap: ${missing[*]}"

    if [[ "$DISTRO" == 'fedora' ]]; then
        run_root dnf install -y --skip-unavailable "${missing[@]}" || true
    else
        run_root emerge --ask=n "${missing[@]}" || true
    fi

    return 0
}

quickshell_version() {
    quickshell --version 2>/dev/null | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true
    return 0
}

version_ge() {
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

mango_version_ok() {
    if [[ "$DISTRO" == gentoo ]]; then
        portageq has_version / '>=gui-wm/mangowm-0.18' >/dev/null 2>&1
        return $?
    fi

    local version=''
    version="$(rpm -q --qf '%{VERSION}' mangowm 2>/dev/null || true)"
    if [[ -z "$version" ]] && command -v mango >/dev/null 2>&1; then
        version="$(mango --version 2>&1 | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)"
    fi
    [[ -n "$version" ]] && version_ge "$version" 0.18
}

selected_mango_needs_upgrade() {
    local comp
    for comp in "${SELECTED_COMPOSITORS[@]}"; do
        if [[ "$comp" == mango ]]; then
            ! mango_version_ok
            return $?
        fi
    done
    return 1
}

ensure_mango_compatible() {
    local comp
    for comp in "${SELECTED_COMPOSITORS[@]}"; do
        if [[ "$comp" != mango ]]; then
            continue
        fi
        if mango_version_ok; then
            return 0
        fi
        log_error 'MangoWM 0.18+ обязателен для конфигурации Serpantinum. Развёртывание отменено.'
        if [[ "$DISTRO" == gentoo ]]; then
            log_error 'Обновите GURU до версии 0.18+ или установите live-версию mangowm-9999 вручную.'
        fi
        return 1
    done
    return 0
}

check_quickshell() {
    local ver

    if ! command -v quickshell >/dev/null 2>&1; then
        log_error "quickshell не установлен — шелл не запустится (нужна версия ${QUICKSHELL_MIN_VERSION}+)."
        FAILED_PKGS+=("quickshell>=${QUICKSHELL_MIN_VERSION}")
        return 1
    fi

    ver="$(quickshell_version)"

    if [[ -z "$ver" ]]; then
        log_warn "quickshell: не удалось определить версию (нужна ${QUICKSHELL_MIN_VERSION}+) — проверьте вручную: quickshell --version"
        return 1
    fi

    if version_ge "$ver" "$QUICKSHELL_MIN_VERSION"; then
        log_info "quickshell: $ver (требуется ${QUICKSHELL_MIN_VERSION}+)"
    else
        log_error "quickshell $ver слишком старый: шеллу нужны Quickshell.Networking/Bluetooth/Polkit (версия ${QUICKSHELL_MIN_VERSION}+). Шелл не запустится — обновите quickshell."
        FAILED_PKGS+=("quickshell>=${QUICKSHELL_MIN_VERSION}(установлен $ver)")
        return 1
    fi

    return 0
}

verify_required_dependencies() {
    local pkg comp failed=0
    for pkg in "${CORE_PKGS[@]}"; do
        if ! pkg_installed "$pkg"; then
            log_error "Обязательный пакет отсутствует: $pkg"
            failed=1
        fi
    done
    for comp in "$@"; do
        if ! is_compositor_installed "$comp"; then
            log_error "Выбранный композитор отсутствует: $comp"
            failed=1
        fi
    done
    check_quickshell || failed=1
    [[ "$failed" -eq 0 ]]
}

install_dependencies() {
    local compositors=("$@")
    local target_list=()
    local comp pkg c

    FAILED_PKGS=()

    if [[ "$DISTRO" == 'fedora' ]]; then
        for pkg in "${REQUIRED_PKGS[@]}"; do
            if [[ "$pkg" == ffmpeg-free ]] && { rpm -q ffmpeg >/dev/null 2>&1 || rpm -q ffmpeg-libs >/dev/null 2>&1; }; then
                log_info 'ffmpeg (RPM Fusion) уже установлен — пропускаю ffmpeg-free'
                continue
            fi
            target_list+=("$pkg")
        done

        if ! rpm -q tuned-ppd >/dev/null 2>&1; then
            target_list+=(power-profiles-daemon)
        fi

        if [[ "$OPT_SDDM" == true && ${#SDDM_PKGS[@]} -gt 0 ]]; then
            target_list+=("${SDDM_PKGS[@]}")
        fi

        if fedora_ensure_copr_plugin; then
            fedora_enable_copr errornointernet/quickshell ||
                log_warn 'COPR errornointernet/quickshell не включился — quickshell может не поставиться'
            fedora_enable_copr solopasha/hyprland ||
                log_warn 'COPR solopasha/hyprland не включился — matugen/satty/hyprland могут не поставиться'
        else
            log_warn 'Плагин dnf copr недоступен — quickshell/matugen из COPR не поставятся'
        fi

        log_info "Fedora: основные пакеты (${#target_list[@]})..."
        run_root dnf install -y --skip-unavailable "${target_list[@]}" || log_warn 'Основная транзакция dnf не полная'

        if [[ ${#OPTIONAL_PKGS[@]} -gt 0 ]]; then
            for pkg in "${OPTIONAL_PKGS[@]}"; do
                if ! pkg_installed "$pkg"; then
                    run_root dnf install -y --skip-unavailable "$pkg" || log_warn "optional: $pkg недоступен"
                fi
            done
        fi

        if [[ ${#compositors[@]} -gt 0 ]]; then
            for comp in "${compositors[@]}"; do
                c="${comp,,}"
                pkg="$(comp_atom "$c")"
                if ! is_compositor_installed "$c" || { [[ "$c" == mango ]] && ! mango_version_ok; }; then
                    if [[ "$c" == hyprland ]]; then
                        if fedora_ensure_copr_plugin; then
                            log_info 'Fedora: подключаю COPR solopasha/hyprland...'
                            fedora_enable_copr solopasha/hyprland ||
                                log_warn 'COPR solopasha/hyprland не включился — hyprland может не установиться'
                        else
                            log_warn 'Плагин dnf copr недоступен — solopasha/hyprland не подключен'
                        fi
                    elif [[ "$c" == niri ]]; then
                        if ! dnf info niri >/dev/null 2>&1; then
                            if fedora_ensure_copr_plugin; then
                                log_info 'Fedora: niri не найден в базовых репозиториях, подключаю COPR yalter/niri...'
                                fedora_enable_copr yalter/niri ||
                                    log_warn 'COPR yalter/niri не включился — niri может не установиться'
                            else
                                log_warn 'Плагин dnf copr недоступен — yalter/niri не подключен'
                            fi
                        fi
                    elif [[ "$c" == mango ]]; then
                        if ! fedora_enable_terra; then
                            log_warn 'Fedora: не удалось подключить Terra — MangoWM не установлен.'
                            FAILED_PKGS+=("$pkg")
                            continue
                        fi
                    fi

                    log_info "Fedora: устанавливаю композитор $pkg..."
                    if [[ "$c" == mango ]] && is_compositor_installed mango; then
                        if ! { run_root dnf upgrade -y "$pkg" || run_root dnf install -y "$pkg"; }; then
                            log_warn "compositor: $pkg не удалось обновить"
                            FAILED_PKGS+=("$pkg")
                        fi
                    elif ! run_root dnf install -y "$pkg"; then
                        log_warn "compositor: $pkg не удалось установить"
                        FAILED_PKGS+=("$pkg")
                    fi
                fi
            done
        fi

        if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
            run_optional_root ln -sfn "$(command -v fdfind)" /usr/local/bin/fd || true
        fi
    else
        target_list=("${REQUIRED_PKGS[@]}")

        local serp_use=(
            "media-video/pipewire dbus extra sound-server"
            "dev-qt/qtmultimedia qml ffmpeg"
            "gui-apps/quickshell layer-shell pipewire screencopy"
        )

        if [[ -d /etc/portage/package.use ]]; then
            run_root tee /etc/portage/package.use/serpantinum >/dev/null <<'EOF_USE' || log_warn 'Gentoo: не удалось записать package.use/serpantinum'
media-video/pipewire dbus extra sound-server
dev-qt/qtmultimedia qml ffmpeg
gui-apps/quickshell layer-shell pipewire screencopy
EOF_USE
        elif [[ -f /etc/portage/package.use ]]; then
            local uflag
            for uflag in "${serp_use[@]}"; do
                if ! grep -Fxq "$uflag" /etc/portage/package.use 2>/dev/null; then
                    printf '%s\n' "$uflag" | run_root tee -a /etc/portage/package.use >/dev/null || true
                fi
            done
        else
            run_root mkdir -p /etc/portage/package.use || log_warn 'Gentoo: не удалось создать /etc/portage/package.use'
            run_root tee /etc/portage/package.use/serpantinum >/dev/null <<'EOF_USE' || log_warn 'Gentoo: не удалось записать package.use/serpantinum'
media-video/pipewire dbus extra sound-server
dev-qt/qtmultimedia qml ffmpeg
gui-apps/quickshell layer-shell pipewire screencopy
EOF_USE
        fi

        gentoo_ensure_guru
        gentoo_sync_tree

        if [[ ${#compositors[@]} -gt 0 ]]; then
            for comp in "${compositors[@]}"; do
                c="${comp,,}"
                if [[ "$c" == hyprland ]]; then
                    gentoo_ensure_hyproverlay
                fi
                if [[ "$c" == mango ]] && ! mango_version_ok; then
                    local mango_atom
                    if ! mango_atom="$(gentoo_mango_release_atom)"; then
                        log_error 'Gentoo: в подключённых репозиториях нет выпуска MangoWM 0.18+. Обновите GURU и повторите установку.'
                        return 1
                    fi
                    target_list+=("$mango_atom")
                else
                    target_list+=("$(comp_atom "$c")")
                fi
            done
        fi

        if [[ "$OPT_SDDM" == true && ${#SDDM_PKGS[@]} -gt 0 ]]; then
            local sddm_atoms=("${SDDM_PKGS[@]}")
            if [[ "$(detect_init_system)" == openrc ]]; then
                sddm_atoms+=(gui-libs/display-manager-init)
            fi
            target_list+=("${sddm_atoms[@]}")
        fi

        if [[ ${#OPTIONAL_PKGS[@]} -gt 0 ]]; then
            local opt_avail=()
            mapfile -t opt_avail < <(gentoo_filter_atoms "${OPTIONAL_PKGS[@]}" 2>/dev/null || true)
            if [[ ${#opt_avail[@]} -gt 0 && -n "${opt_avail[0]}" ]]; then
                target_list+=("${opt_avail[@]}")
            fi
        fi

        local filtered=()
        mapfile -t filtered < <(gentoo_filter_atoms "${target_list[@]}")
        if [[ ${#filtered[@]} -gt 0 ]]; then
            target_list=("${filtered[@]}")
        fi

        if ! gentoo_autounmask_resolve "${target_list[@]}"; then
            log_warn 'Gentoo: autounmask не завершился чисто'
        fi

        run_root emerge --ask=n --newuse --autounmask-continue "${target_list[@]}" || log_warn 'Gentoo: emerge не полный'
    fi

    for pkg in "${target_list[@]}"; do
        if ! pkg_installed "$pkg"; then
            FAILED_PKGS+=("$pkg")
        fi
    done

    if [[ ${#FAILED_PKGS[@]} -eq 0 ]]; then
        log_ok 'Зависимости установлены.'
    else
        log_warn "Не установлены пакеты: ${FAILED_PKGS[*]}"
    fi

    verify_required_dependencies "${compositors[@]}"
}

detect_init_system() {
    local p

    if [[ -n "${LINKA_INIT_SYSTEM:-}" ]]; then
        printf '%s\n' "$LINKA_INIT_SYSTEM"
        return 0
    fi
    p="$(ps -p 1 -o comm= 2>/dev/null || true)"

    if [[ "$p" == systemd && -d /run/systemd/system ]]; then
        printf 'systemd\n'
        return 0
    fi

    if [[ -d /run/openrc || "$p" == openrc-init ]]; then
        printf 'openrc\n'
        return 0
    fi

    printf 'generic\n'
    return 0
}

ensure_update_dependencies() {
    bootstrap_installer_deps || true

    local missing=()
    local cmd comp
    local comps=()

    if [[ ${#SELECTED_COMPOSITORS[@]} -gt 0 ]]; then
        comps=("${SELECTED_COMPOSITORS[@]}")
    elif [[ ${#SELECTED_COMPOSITORS_SAVED[@]} -gt 0 ]]; then
        comps=("${SELECTED_COMPOSITORS_SAVED[@]}")
    fi

    for cmd in matugen quickshell; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    for cmd in "${CORE_PKGS[@]}"; do
        if ! pkg_installed "$cmd"; then
            missing+=("$cmd")
        fi
    done

    for comp in "${comps[@]}"; do
        if ! is_compositor_installed "$comp"; then
            missing+=("$comp")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Для обновления не хватает: ${missing[*]}"
        log_info 'Пытаюсь доставить зависимости через install_dependencies'

        if [[ ${#comps[@]} -gt 0 ]]; then
            install_dependencies "${comps[@]}" || return 1
        else
            install_dependencies || return 1
        fi
    fi

    verify_required_dependencies "${comps[@]}"
}
