gentoo_ensure_guru() {
    if [[ -f /var/db/repos/guru/profiles/repo_name ]]; then
        return 0
    fi

    log_info 'Gentoo: подключаю overlay guru...'

    if [[ -e /var/db/repos/guru ]]; then
        local guru_bak
        guru_bak="/var/db/repos/guru.linka-bak.$(date +%Y%m%d_%H%M%S)"
        if run_root mv /var/db/repos/guru "$guru_bak" 2>/dev/null; then
            log_warn "Каталог /var/db/repos/guru не содержал валидного профиля оверлея и перемещён в $guru_bak"
        else
            log_warn "Не удалось забэкапить невалидный /var/db/repos/guru — пропускаю подключение оверлея."
            return 0
        fi
    fi

    if command -v eselect >/dev/null 2>&1 && eselect modules list 2>/dev/null | grep -qw repository; then
        if run_root eselect repository enable guru; then
            log_ok 'guru включён через eselect repository.'
            run_root emaint sync -r guru || true
            if [[ -f /var/db/repos/guru/profiles/repo_name ]]; then
                return 0
            fi
        fi
    fi

    run_root mkdir -p /var/db/repos /etc/portage/repos.conf || true

    if run_root git clone --depth 1 https://github.com/gentoo-mirror/guru.git /var/db/repos/guru; then
        if [[ -d /etc/portage/repos.conf ]]; then
            if run_root tee /etc/portage/repos.conf/guru.conf >/dev/null <<'EOF_GURU'
[guru]
location = /var/db/repos/guru
sync-type = git
sync-uri = https://github.com/gentoo-mirror/guru.git
auto-sync = yes
EOF_GURU
            then
                log_ok 'guru подключён.'
            else
                log_warn 'guru: не удалось записать repos.conf'
            fi
        elif [[ -f /etc/portage/repos.conf ]]; then
            if ! grep -q '\[guru\]' /etc/portage/repos.conf 2>/dev/null; then
                run_root tee -a /etc/portage/repos.conf >/dev/null <<'EOF_GURU'

[guru]
location = /var/db/repos/guru
sync-type = git
sync-uri = https://github.com/gentoo-mirror/guru.git
auto-sync = yes
EOF_GURU
            fi
            log_ok 'guru подключён в /etc/portage/repos.conf.'
        fi
    else
        log_warn 'guru не подключился — quickshell/matugen могут не установиться.'
    fi

    return 0
}

gentoo_ensure_hyproverlay() {
    if [[ -f /var/db/repos/hyproverlay/profiles/repo_name ]]; then
        return 0
    fi

    log_info 'Gentoo: подключаю overlay hyproverlay...'

    if [[ -e /var/db/repos/hyproverlay ]]; then
        local hypr_bak
        hypr_bak="/var/db/repos/hyproverlay.linka-bak.$(date +%Y%m%d_%H%M%S)"
        if run_root mv /var/db/repos/hyproverlay "$hypr_bak" 2>/dev/null; then
            log_warn "Каталог /var/db/repos/hyproverlay не содержал валидного профиля оверлея и перемещён в $hypr_bak"
        else
            log_warn "Не удалось забэкапить невалидный /var/db/repos/hyproverlay — пропускаю подключение оверлея."
            return 0
        fi
    fi

    if command -v eselect >/dev/null 2>&1 && eselect modules list 2>/dev/null | grep -qw repository; then
        if run_root eselect repository enable hyproverlay; then
            log_ok 'hyproverlay включён через eselect repository.'
            run_root emaint sync -r hyproverlay || true
            if [[ -f /var/db/repos/hyproverlay/profiles/repo_name ]]; then
                return 0
            fi
        fi
    fi

    run_root mkdir -p /var/db/repos /etc/portage/repos.conf || true

    if run_root git clone --depth 1 https://codeberg.org/hyproverlay/hyproverlay.git /var/db/repos/hyproverlay; then
        if [[ -d /etc/portage/repos.conf ]]; then
            if run_root tee /etc/portage/repos.conf/hyproverlay.conf >/dev/null <<'EOF_HYPR'
[hyproverlay]
location = /var/db/repos/hyproverlay
sync-type = git
sync-uri = https://codeberg.org/hyproverlay/hyproverlay.git
auto-sync = yes
EOF_HYPR
            then
                log_ok 'hyproverlay подключён.'
            else
                log_warn 'hyproverlay: не удалось записать repos.conf'
            fi
        elif [[ -f /etc/portage/repos.conf ]]; then
            if ! grep -q '\[hyproverlay\]' /etc/portage/repos.conf 2>/dev/null; then
                run_root tee -a /etc/portage/repos.conf >/dev/null <<'EOF_HYPR'

[hyproverlay]
location = /var/db/repos/hyproverlay
sync-type = git
sync-uri = https://codeberg.org/hyproverlay/hyproverlay.git
auto-sync = yes
EOF_HYPR
            fi
            log_ok 'hyproverlay подключён в /etc/portage/repos.conf.'
        fi
    else
        log_warn 'hyproverlay не подключился — gui-wm/hyprland может не установиться.'
    fi

    return 0
}

gentoo_sync_tree() {
    if [[ ! -f /var/db/repos/gentoo/profiles/repo_name ]]; then
        log_info 'Gentoo: дерево отсутствует, запускаю emerge-webrsync...'
        run_root emerge-webrsync || log_warn 'webrsync не удался'
    elif [[ -d /var/db/repos/guru ]]; then
        run_root emaint sync -r guru >/dev/null 2>&1 || true
    fi
    return 0
}

gentoo_mango_release_atom() {
    command -v portageq >/dev/null 2>&1 || return 1

    local repo path ebuild version best=''
    for repo in $(portageq get_repos / 2>/dev/null); do
        path="$(portageq get_repo_path / "$repo" 2>/dev/null || true)"
        [[ -n "$path" ]] || continue
        for ebuild in "$path"/gui-wm/mangowm/mangowm-[0-9]*.ebuild; do
            [[ -f "$ebuild" ]] || continue
            version="${ebuild##*/mangowm-}"
            version="${version%.ebuild}"
            [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-r[0-9]+)?$ ]] || continue
            if version_ge "$version" 0.18 && { [[ -z "$best" ]] || version_ge "$version" "$best"; }; then
                best="$version"
            fi
        done
    done

    [[ -n "$best" ]] || return 1
    printf '=gui-wm/mangowm-%s\n' "$best"
}

gentoo_filter_atoms() {
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    local repo_paths=() out=() miss=()
    local r rp atom c p found clean_atom

    if command -v portageq >/dev/null 2>&1; then
        for r in $(portageq get_repos / 2>/dev/null || true); do
            rp="$(portageq get_repo_path / "$r" 2>/dev/null || true)"
            if [[ -n "$rp" ]]; then
                repo_paths+=("$rp")
            fi
        done
    fi

    if [[ ${#repo_paths[@]} -eq 0 ]]; then
        printf '%s\n' "$@"
        return 0
    fi

    for atom in "$@"; do
        clean_atom="${atom#[><=~]}"
        c="${clean_atom%%/*}"
        p="${clean_atom##*/}"
        p="${p%%:*}"
        p="${p%%-[0-9]*}"
        found=0

        for rp in "${repo_paths[@]}"; do
            if [[ -d "$rp/$c/$p" ]]; then
                found=1
                break
            fi
        done

        if [[ "$found" -eq 1 ]]; then
            out+=("$atom")
        else
            miss+=("$atom")
        fi
    done

    if [[ ${#miss[@]} -gt 0 ]]; then
        log_warn "Gentoo: атомы не найдены в репозиториях и пропущены: ${miss[*]}"
    fi

    if [[ ${#out[@]} -gt 0 ]]; then
        printf '%s\n' "${out[@]}"
    elif [[ $# -gt 0 ]]; then
        printf '%s\n' "$@"
    fi

    return 0
}

gentoo_apply_autounmask_cfg() {
    local cfg_file target_file base name temp size
    for cfg_file in "$@"; do
        [[ -f "$cfg_file" && ! -L "$cfg_file" ]] || return 1
        base="${cfg_file##*/}"
        [[ "$base" =~ ^\._cfg[0-9]+_(.+)$ ]] || return 1
        name="${BASH_REMATCH[1]}"
        target_file="${cfg_file%/*}/$name"
        [[ ! -L "$target_file" ]] || return 1
        if [[ -f "$target_file" ]]; then
            size="$(run_root stat -c %s -- "$cfg_file")" || return 1
            if [[ "$size" -gt 0 ]] && run_root tail -c "$size" -- "$target_file" | run_root cmp -s -- "$cfg_file" -; then
                run_root rm -f -- "$cfg_file" || return 1
                continue
            fi
            temp="$(run_root mktemp "${target_file}.linka.XXXXXXXX")" || return 1
            if ! run_root cp -a -- "$target_file" "$temp" ||
               ! run_root cat -- "$cfg_file" | run_root tee -a -- "$temp" >/dev/null ||
               ! run_root mv -fT -- "$temp" "$target_file"; then
                run_root rm -f -- "$temp" || true
                log_error "Не удалось применить $cfg_file; исходник сохранён."
                return 1
            fi
            run_root rm -f -- "$cfg_file" || return 1
        else
            run_root mv -- "$cfg_file" "$target_file" || return 1
        fi
    done
    return 0
}

gentoo_pending_autounmask_cfg() {
    local root="${PORTAGE_ROOT:-/etc/portage}"
    find "$root" -maxdepth 2 -type f -name '._cfg[0-9]*_*' -print0 2>/dev/null | sort -z
}

gentoo_autounmask_resolve() {
    local round_i before after cfg
    local created=()

    if [[ $# -eq 0 ]]; then
        return 0
    fi

    for round_i in 1 2 3 4 5; do
        if emerge --pretend "$@" >/dev/null 2>&1; then
            return 0
        fi

        log_info "Gentoo: autounmask (круг $round_i)..."
        before="$(mktemp)" || return 1
        after="$(mktemp)" || { rm -f "$before"; return 1; }
        gentoo_pending_autounmask_cfg > "$before"
        run_root emerge --pretend --autounmask=y --autounmask-write=y "$@" >/dev/null 2>&1 || true
        gentoo_pending_autounmask_cfg > "$after"
        created=()
        while IFS= read -r -d '' cfg; do
            created+=("$cfg")
        done < <(comm -z -13 "$before" "$after")
        rm -f "$before" "$after"
        if [[ ${#created[@]} -eq 0 ]]; then
            log_error 'Gentoo: autounmask не создал новых изменений; старые файлы оставлены без изменений.'
            return 1
        fi
        gentoo_apply_autounmask_cfg "${created[@]}" || return 1
    done

    if emerge --pretend "$@" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}
