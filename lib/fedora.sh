fedora_ensure_copr_plugin() {
    local dnf_cmd="dnf"
    if ! command -v dnf >/dev/null 2>&1 && command -v dnf5 >/dev/null 2>&1; then
        dnf_cmd="dnf5"
    fi

    if "$dnf_cmd" copr --help >/dev/null 2>&1; then
        return 0
    fi

    log_info 'Fedora: ставлю плагин dnf copr...'

    local plugin_pkg="dnf-plugins-core"
    if "$dnf_cmd" --version 2>/dev/null | grep -q -E '^(dnf5|5\.)'; then
        plugin_pkg="dnf5-plugins"
    fi

    run_root "$dnf_cmd" install -y "$plugin_pkg" >/dev/null 2>&1 ||
        run_root "$dnf_cmd" install -y dnf-plugins-core >/dev/null 2>&1 ||
        return 1

    "$dnf_cmd" copr --help >/dev/null 2>&1
}

fedora_enable_copr() {
    local repo="$1"
    local dnf_cmd="dnf"
    if ! command -v dnf >/dev/null 2>&1 && command -v dnf5 >/dev/null 2>&1; then
        dnf_cmd="dnf5"
    fi

    fedora_ensure_copr_plugin || return 1
    run_root "$dnf_cmd" copr enable -y "$repo"
}

fedora_enable_terra() {
    if rpm -q terra-release >/dev/null 2>&1; then
        return 0
    fi

    log_info 'Fedora: подключаю репозиторий Terra для MangoWM...'
    run_root dnf install -y --nogpgcheck --repofrompath \
        'terra,https://repos.fyralabs.com/terra$releasever' terra-release
}
