ensure_ownership_marker() {
    mkdir -p "$TARGET_BASE"

    if [[ ! -f "$OWNERSHIP_MARKER" ]]; then
        printf 'owner=linka\nversion=%s\nrepo=%s\n' "$LINKA_VERSION" "$REPO_SLUG" > "$OWNERSHIP_MARKER"
    fi

    return 0
}

get_compositor_config_dir_name() {
    case "$1" in
        hyprland) printf 'hypr\n' ;;
        niri)     printf 'niri\n' ;;
        sway)     printf 'sway\n' ;;
        mango)    printf 'mango\n' ;;
        *)        printf '%s\n' "$1" ;;
    esac
}

compositor_config_needs_deploy() {
    local comp="$1"
    local dir
    dir="$HOME/.config/$(get_compositor_config_dir_name "$comp")"

    if [[ "$comp" == mango ]]; then
        [[ ! -f "$dir/config.conf" ]]
        return $?
    fi

    [[ ! -d "$dir" || -z "$(ls -A "$dir" 2>/dev/null || true)" ]]
}

selected_compositor_config_missing() {
    local comp
    for comp in "${SELECTED_COMPOSITORS[@]}"; do
        [[ -d "$PROJECT_ROOT/compositors/$comp" || -d "$PROJECT_ROOT/compositor/$comp" ]] || continue
        if [[ "$comp" == mango && " ${SELECTED_COMPOSITORS_SAVED[*]} " != *" mango "* ]]; then
            return 0
        fi
        if compositor_config_needs_deploy "$comp"; then
            return 0
        fi
    done
    return 1
}

deploy_compositor_config() {
    local repo="$1"
    local c="$2"
    local dn src tgt

    dn="$(get_compositor_config_dir_name "$c")"
    src=''

    if [[ -d "$repo/compositors/$c" ]]; then
        src="$repo/compositors/$c"
    fi

    if [[ -z "$src" && -d "$repo/compositor/$c" ]]; then
        src="$repo/compositor/$c"
    fi

    if [[ -z "$src" ]]; then
        return 0
    fi

    tgt="$HOME/.config/$dn"
    if [[ -L "$tgt" ]]; then
        log_warn "$HOME/.config/$dn — симлинк; пропускаю развёртывание, чтобы не менять его целевой каталог."
        return 0
    fi
    if ! backup_user_config "$dn"; then
        log_warn "Пропускаю развёртывание конфига $c в ~/.config/$dn, так как бэкап не удался."
        return 1
    fi
    mkdir -p "$tgt"
    if ! cp -a --remove-destination "$src/." "$tgt/"; then
        log_error "Не удалось развернуть конфиг $c в ~/.config/$dn"
        return 1
    fi
    log_ok "Конфиг $c развёрнут в ~/.config/$dn"

    return 0
}

prune_removed_files() {
    local repo="$1"
    local oc="$2"
    local f deleted_tmp removed=0

    if [[ -z "$oc" || "$oc" == unknown || ! -d "$repo/.git" ]]; then
        return 1
    fi

    if ! git -C "$repo" cat-file -e "${oc}^{commit}" 2>/dev/null; then
        return 1
    fi

    deleted_tmp="$(mktemp)" || return 1

    if ! git -C "$repo" diff -z --name-only --no-renames --diff-filter=D "$oc" HEAD -- bin src > "$deleted_tmp" 2>/dev/null; then
        rm -f "$deleted_tmp"
        return 1
    fi

    while IFS= read -r -d '' f; do
        if [[ -e "$TARGET_BASE/$f" || -L "$TARGET_BASE/$f" ]]; then
            rm -f "$TARGET_BASE/$f"
            removed=$((removed+1))
        fi
    done < "$deleted_tmp"

    rm -f "$deleted_tmp"

    if [[ "$removed" -gt 0 ]]; then
        find "$TARGET_BASE/bin" "$TARGET_BASE/src" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        log_info "Удалено устаревших файлов (были в старой версии, нет в новой): $removed"
    fi

    return 0
}

deploy_incremental() {
    local repo="$1"
    local oc="$2"
    local f

    if [[ "$FORCE_UPDATE" == 1 || -z "$oc" || "$oc" == unknown || ! -d "$repo/.git" ]]; then
        return 1
    fi

    if [[ ! -d "$TARGET_BASE/src" ]]; then
        return 1
    fi

    if ! git -C "$repo" cat-file -e "${oc}^{commit}" 2>/dev/null; then
        return 1
    fi

    local changed_tmp
    changed_tmp="$(mktemp)" || return 1

    if ! git -C "$repo" diff -z --name-only --no-renames --diff-filter=AMT "$oc" HEAD -- bin src > "$changed_tmp" 2>/dev/null; then
        rm -f "$changed_tmp"
        return 1
    fi

    prune_removed_files "$repo" "$oc" || {
        rm -f "$changed_tmp"
        return 1
    }

    local cp_failed=0

    while IFS= read -r -d '' f; do
        if [[ -L "$TARGET_BASE/$(dirname "$f")" ]]; then
            cp_failed=1
            continue
        fi
        if ! mkdir -p "$(dirname "$TARGET_BASE/$f")" ||
           ! cp -a --remove-destination -- "$repo/$f" "$TARGET_BASE/$f"; then
            cp_failed=1
            log_warn "Не удалось скопировать: $f"
            continue
        fi

        if [[ "$f" == bin/* || "$f" == *.sh ]]; then
            chmod +x "$TARGET_BASE/$f" 2>/dev/null || true
        fi
    done < "$changed_tmp"

    rm -f "$changed_tmp"

    if [[ "$cp_failed" -eq 1 ]]; then
        log_warn 'Инкрементальное обновление прошло с ошибками — перехожу на полное копирование'
        return 1
    fi

    log_info "Инкрементальное обновление: $oc → $(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo HEAD)"
    return 0
}

copy_tree_full() {
    local repo="$1"

    if [[ -d "$repo/bin" ]]; then
        cp -a "$repo/bin/." "$TARGET_BASE/bin/" || return 1
    fi

    if [[ -d "$repo/src" ]]; then
        cp -a "$repo/src/." "$TARGET_BASE/src/" || return 1
    fi

    if [[ -f "$repo/version.txt" ]]; then
        cp -a "$repo/version.txt" "$TARGET_BASE/version.txt" 2>/dev/null || true
    fi

    return 0
}

fix_exec_bits() {
    find "$TARGET_BASE/src" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
    find "$TARGET_BASE/bin" -type f -exec chmod +x {} + 2>/dev/null || true
    return 0
}

verify_deploy() {
    local repo="$1"
    local f rel bad=0 missing=0

    for rel in bin/serpantinumd bin/serpantinum; do
        if [[ -f "$repo/$rel" && ! -x "$TARGET_BASE/$rel" ]]; then
            log_warn "Проверка деплоя: $rel отсутствует или не исполняемый"
            bad=1
        fi
    done

    if [[ -d "$repo/src/quickshell" && ! -d "$TARGET_BASE/src/quickshell" ]]; then
        log_warn 'Проверка деплоя: нет каталога src/quickshell'
        bad=1
    fi

    if [[ -d "$repo/.git" ]]; then
        while IFS= read -r -d '' f; do
            if [[ ! -e "$TARGET_BASE/$f" && ! -L "$TARGET_BASE/$f" ]]; then
                missing=$((missing+1))
                if [[ "$missing" -le 5 ]]; then
                    log_warn "Проверка деплоя: нет файла $f"
                fi
            elif [[ -L "$repo/$f" ]]; then
                if [[ ! -L "$TARGET_BASE/$f" || "$(readlink -- "$repo/$f")" != "$(readlink -- "$TARGET_BASE/$f")" ]]; then
                    log_warn "Проверка деплоя: неверный симлинк $f"
                    bad=1
                fi
            elif [[ ! -f "$TARGET_BASE/$f" || -L "$TARGET_BASE/$f" ]] || ! cmp -s -- "$repo/$f" "$TARGET_BASE/$f"; then
                log_warn "Проверка деплоя: неверное содержимое или тип $f"
                bad=1
            fi
        done < <(git -C "$repo" ls-files -z -- bin src 2>/dev/null)
    fi

    if [[ "$missing" -gt 0 ]]; then
        log_warn "Проверка деплоя: не хватает файлов: $missing"
        bad=1
    fi

    if [[ "$bad" -ne 0 ]]; then
        return 1
    fi

    return 0
}

deploy_full() {
    local repo="$1"
    local is_update="$2"
    shift 2

    local comps=("$@")
    local c src tgt backup_dir

    CONFIG_BACKUP_DIR=""

    if [[ ! -d "$repo" ]]; then
        return 1
    fi

    if [[ ! -d "$repo/bin" && ! -d "$repo/src" ]]; then
        log_error 'В репозитории нет каталогов bin/ и src/.'
        return 1
    fi

    if [[ "$is_update" == true ]]; then
        mkdir -p "$TARGET_BASE/bin" "$TARGET_BASE/src" "$BIN_DIR"
        ensure_ownership_marker
    else
        if [[ -e "$TARGET_BASE" ]]; then
            mkdir -p "$BACKUP_BASE"
            backup_dir="${BACKUP_BASE}/target.$(date +%Y%m%d_%H%M%S)"

            if ! mv "$TARGET_BASE" "$backup_dir"; then
                log_error "Не удалось переместить старый $TARGET_BASE в $backup_dir: переустановка прервана, ничего не удалено."
                return 1
            fi
        fi

        mkdir -p "$TARGET_BASE/bin" "$TARGET_BASE/src" "$BIN_DIR"
        ensure_ownership_marker
    fi

    local incremental_ok=false

    if [[ "$is_update" == true ]] && deploy_incremental "$repo" "$DEPLOY_OLD_COMMIT"; then
        incremental_ok=true
    else
        copy_tree_full "$repo" || return 1

        if [[ "$is_update" == true ]]; then
            if ! prune_removed_files "$repo" "$DEPLOY_OLD_COMMIT"; then
                log_warn 'Не удалось определить устаревшие файлы (старый коммит недоступен) — в target могли остаться лишние файлы; чтобы убрать их, выполните linka reinstall.'
            fi
        fi
    fi

    fix_exec_bits

    if ! verify_deploy "$repo"; then
        if [[ "$incremental_ok" == true ]]; then
            log_warn 'Проверка после инкрементального обновления не прошла — делаю полное копирование.'
            copy_tree_full "$repo" || return 1
            fix_exec_bits

            if ! verify_deploy "$repo"; then
                log_error 'Деплой не прошёл проверку целостности.'
                return 1
            fi
        else
            log_error 'Деплой не прошёл проверку целостности.'
            return 1
        fi
    fi

    if [[ "$is_update" != true ]]; then
        for c in kitty cava fastfetch; do
            src="$repo/config/$c"
            tgt="$HOME/.config/$c"

            if [[ -e "$src" ]]; then
                if [[ -L "$tgt" ]]; then
                    log_warn "$HOME/.config/$c — симлинк; пропускаю развёртывание, чтобы не менять его целевой каталог."
                    continue
                fi
                if ! backup_user_config "$c"; then
                    log_error "Не удалось сохранить конфиг $c перед развёртыванием."
                    return 1
                fi
                mkdir -p "$(dirname "$tgt")"

                if [[ -d "$src" ]]; then
                    mkdir -p "$tgt"
                    if ! cp -a --remove-destination "$src/." "$tgt/"; then
                        log_error "Не удалось развернуть конфиг $c в ~/.config/$c"
                        return 1
                    fi
                else
                    if ! cp -a --remove-destination "$src" "$tgt"; then
                        log_error "Не удалось развернуть конфиг $c в ~/.config/$c"
                        return 1
                    fi
                fi
            fi
        done

        if [[ ${#comps[@]} -gt 0 ]]; then
            for c in "${comps[@]}"; do
                deploy_compositor_config "$repo" "$c" || return 1
            done
        fi
    else
        if [[ ${#comps[@]} -gt 0 ]]; then
            for c in "${comps[@]}"; do
                if compositor_config_needs_deploy "$c"; then
                    deploy_compositor_config "$repo" "$c" || return 1
                fi
            done
        fi
    fi

    return 0
}

deploy_package() {
    local repo="$1"
    local oc="$2"
    local nc="$3"
    local rei="$4"
    local ist="$5"
    shift 5

    local comps=("$@")
    local iu=false

    : "$nc"
    DEPLOY_OLD_COMMIT="$oc"

    if [[ "$ist" == current && "$rei" != true ]]; then
        iu=true
    fi

    if [[ ${#comps[@]} -gt 0 ]]; then
        deploy_full "$repo" "$iu" "${comps[@]}" || return 1
    else
        deploy_full "$repo" "$iu" || return 1
    fi

    if [[ -f "$TARGET_BASE/bin/serpantinum" || -f "$TARGET_BASE/bin/serpantinumd" ]]; then
        run_optional_root mkdir -p /usr/local/bin || true
    fi

    if [[ -f "$TARGET_BASE/bin/serpantinum" ]]; then
        ln -sfn "$TARGET_BASE/bin/serpantinum" "$BIN_DIR/serpantinum"
        run_optional_root ln -sfn "$TARGET_BASE/bin/serpantinum" /usr/local/bin/serpantinum || true
    fi

    if [[ -f "$TARGET_BASE/bin/serpantinumd" ]]; then
        ln -sfn "$TARGET_BASE/bin/serpantinumd" "$BIN_DIR/serpantinumd"
        run_optional_root ln -sfn "$TARGET_BASE/bin/serpantinumd" /usr/local/bin/serpantinumd || true
    fi

    return 0
}

matugen_supports_source_color_index() {
    local help

    if ! command -v matugen >/dev/null 2>&1; then
        return 2
    fi

    help="$(matugen image --help 2>&1 || true)"

    if [[ -z "$help" ]]; then
        return 2
    fi

    if grep -q -- '--source-color-index' <<< "$help"; then
        return 0
    fi

    return 1
}

fix_matugen_compat() {
    if [[ "${SERPANTINUM_MATUGEN_COMPAT:-auto}" == "0" ]]; then
        return 0
    fi

    local qml="$TARGET_BASE/src/quickshell/singletons/theme/Matugen.qml"
    local cfg="$TARGET_BASE/src/assets/matugen/config.toml"
    local tpl="$TARGET_BASE/src/assets/matugen/templates"
    local rc=0

    matugen_supports_source_color_index || rc=$?

    if [[ "$rc" -eq 1 && -f "$qml" ]] && grep -q 'source-color-index' "$qml"; then
        local qml_bak="${qml}.linka-bak"
        cp -a "$qml" "$qml_bak" 2>/dev/null || true

        if sed -i '/source-color-index/d' "$qml"; then
            log_ok 'Matugen: убран флаг --source-color-index (не поддерживается установленным matugen)'
        else
            mv -f "$qml_bak" "$qml" 2>/dev/null || true
            log_warn 'Не удалось безопасно применить matugen QML compat'
        fi
    fi

    if [[ -f "$cfg" && -d "$tpl" ]] && grep -q 'input_path = "templates/' "$cfg"; then
        local cfg_bak="${cfg}.linka-bak"
        cp -a "$cfg" "$cfg_bak" 2>/dev/null || true

        if sed -i "s|input_path = \"templates/|input_path = \"$tpl/|g" "$cfg"; then
            log_ok 'Matugen: пути шаблонов сделаны абсолютными'
        else
            mv -f "$cfg_bak" "$cfg" 2>/dev/null || true
            log_warn 'Не удалось поправить matugen config.toml'
        fi
    fi

    return 0
}

matugen_needs_repair() {
    local repo_qml="$1/src/quickshell/singletons/theme/Matugen.qml"
    local target_qml="$TARGET_BASE/src/quickshell/singletons/theme/Matugen.qml"
    local rc=0

    if [[ "${SERPANTINUM_MATUGEN_COMPAT:-auto}" == "0" ]]; then
        return 1
    fi

    if [[ -f "$repo_qml" && ! -f "$target_qml" ]]; then
        return 0
    fi

    if [[ -f "$repo_qml" && -f "$target_qml" ]]; then
        matugen_supports_source_color_index || rc=$?

        if [[ "$rc" -eq 0 ]] &&
           grep -q 'source-color-index' "$repo_qml" 2>/dev/null &&
           ! grep -q 'source-color-index' "$target_qml" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

merge_serpantinum_config() {
    local repo="$1"
    local tj="$repo/config/serpantinum/settings.json"
    local tmp wp lang

    [[ ! -L "$CONFIG_DIR" ]] || return 1
    mkdir -p "$CONFIG_DIR" || return 1

    if [[ ! -f "$tj" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            printf '{}\n' > "$CONFIG_FILE"
        fi
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            cp -a "$tj" "$CONFIG_FILE" 2>/dev/null || true
        fi
        return 0
    fi

    wp="$(get_wallpaper_dir)"
    lang="$(detect_system_language "$repo")"

    if [[ ! -f "$CONFIG_FILE" || ! -s "$CONFIG_FILE" ]]; then
        tmp="$(mktemp "$CONFIG_DIR/.settings.XXXXXX")" || return 0

        if jq --arg wp "$wp" --arg lang "$lang" '
            . + (if ($wp|length)>0 then {wallpaperDir:$wp} else {} end)
            | if ((.general.language // "") | length) == 0
              then .general = ((.general // {}) + {language:$lang})
              else .
              end
        ' "$tj" > "$tmp" 2>/dev/null; then
            chmod 600 "$tmp" 2>/dev/null || true
            mv -f "$tmp" "$CONFIG_FILE"
        else
            rm -f "$tmp"
            cp -a "$tj" "$CONFIG_FILE" 2>/dev/null || true
        fi

        return 0
    fi

    tmp="$(mktemp "$CONFIG_DIR/.settings.XXXXXX")" || return 0

    if jq -s --arg wp "$wp" --arg lang "$lang" '
        (.[0] * .[1])
        | if ((.wallpaperDir // "") | length) == 0 and ($wp|length)>0
          then .wallpaperDir = $wp
          else .
          end
        | if ((.general.language // "") | length) == 0
          then .general = ((.general // {}) + {language:$lang})
          else .
          end
    ' "$tj" "$CONFIG_FILE" > "$tmp" 2>/dev/null; then
        chmod 600 "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$CONFIG_FILE"
    else
        rm -f "$tmp"
        log_warn "Не удалось смержить settings.json; оставляю пользовательский конфиг"
    fi

    return 0
}

run_user_post_update_hook() {
    local user_hook="$CONFIG_DIR/hooks/post_update.sh"
    if [[ ! -e "$user_hook" ]]; then
        return 0
    fi
    if [[ ! -x "$user_hook" ]]; then
        log_warn "Пользовательский хук $user_hook найден, но не имеет прав на выполнение (chmod +x)."
        return 0
    fi

    log_info "Выполняю пользовательский хук: $user_hook"
    (
        export TARGET_DIR="${TARGET_DIR:-$TARGET_BASE}"
        export TARGET_BASE="$TARGET_BASE"
        export CONFIG_DIR="$CONFIG_DIR"
        exec 9>&- 8>&-
        "$user_hook"
    ) || { log_error "Пользовательский хук завершился с ошибкой ($?)"; return 1; }

    return 0
}
