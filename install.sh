#!/usr/bin/env bash
# ==============================================================================
#  linka — Serpantinum Installer & Updater for Gentoo & Fedora Linux
#  Repository: https://github.com/Tkanchik/linka
# ==============================================================================
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/Tkanchik/linka/main/linka"
BIN_DIR="${HOME}/.local/bin"
LINKA_BIN="${BIN_DIR}/linka"

echo -e "\033[1;36m==>\033[0m \033[1mЗагрузка linka (установщик Serpantinum для Gentoo/Fedora)...\033[0m"
mkdir -p "${BIN_DIR}"
curl -fsSL "${REPO_RAW}" -o "${LINKA_BIN}"
chmod +x "${LINKA_BIN}"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    export PATH="${BIN_DIR}:${PATH}"
fi

echo -e "\033[1;32m==>\033[0m \033[1mlinka установлена в ${LINKA_BIN}\033[0m"

# Если запуск был через конвейер (curl ... | bash), переподключаем STDIN к терминалу
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec < /dev/tty
fi

exec "${LINKA_BIN}" "${@:-}"
