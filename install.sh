#!/usr/bin/env bash
# ==============================================================================
#  linka — Serpantinum Installer & Updater for Gentoo & Fedora Linux
#  Repository: https://github.com/Tkanchik/linka
# ==============================================================================
set -Eeuo pipefail

REPO_URL="https://github.com/Tkanchik/linka.git"
SHARE_DIR="${HOME}/.local/share/linka"
BIN_DIR="${HOME}/.local/bin"
LINKA_SYMLINK="${BIN_DIR}/linka"

echo -e "\033[1;36m==>\033[0m \033[1mРазвёртывание linka (Gentoo/Fedora установщик для Serpantinum)...\033[0m"

# Проверка наличия git
if ! command -v git &>/dev/null; then
    echo -e "\033[1;33m[вним]\033[0m git не найден в системе. Пожалуйста, установите git и запустите снова."
    exit 1
fi

mkdir -p "${BIN_DIR}"
mkdir -p "$(dirname "${SHARE_DIR}")"

if [ ! -d "${SHARE_DIR}/.git" ]; then
    rm -rf "${SHARE_DIR}"
    git clone "${REPO_URL}" "${SHARE_DIR}"
else
    git -C "${SHARE_DIR}" pull --ff-only 2>/dev/null || true
fi

chmod +x "${SHARE_DIR}/linka"
ln -sfn "${SHARE_DIR}/linka" "${LINKA_SYMLINK}"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    export PATH="${BIN_DIR}:${PATH}"
fi

echo -e "\033[1;32m==>\033[0m \033[1mlinka успешно установлена в ${LINKA_SYMLINK}\033[0m"

# Если запуск производился через пайп (curl ... | bash), переподключаем ввод к терминалу
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec < /dev/tty
fi

exec "${LINKA_SYMLINK}" "${@:-}"
