#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/Tkanchik/linka.git"
SHARE_DIR="${HOME}/.local/share/linka"
BIN_DIR="${HOME}/.local/bin"
LINKA_SYMLINK="${BIN_DIR}/linka"

echo -e "\033[1;36m==>\033[0m \033[1mРазвёртывание linka (Gentoo/Fedora установщик для Serpantinum)...\033[0m"

if ! command -v git &>/dev/null; then
    echo -e "\033[1;33m[вним]\033[0m git не найден в системе. Пожалуйста, установите git и запустите снова."
    exit 1
fi

mkdir -p "${BIN_DIR}"
mkdir -p "$(dirname "${SHARE_DIR}")"

if [[ ! -e "${SHARE_DIR}" && ! -L "${SHARE_DIR}" ]]; then
    git clone "${REPO_URL}" "${SHARE_DIR}"
else
    if [[ -L "${SHARE_DIR}" ]]; then
        echo "[ошибка] ${SHARE_DIR} является симлинком. Укажите обычный каталог репозитория linka." >&2
        exit 1
    fi
    if [[ ! -d "${SHARE_DIR}/.git" ]]; then
        echo "[ошибка] ${SHARE_DIR} уже существует и не является репозиторием linka." >&2
        exit 1
    fi
    origin_url="$(git -C "${SHARE_DIR}" config --local --get remote.origin.url)" || {
        echo "[ошибка] Не удалось прочитать origin в ${SHARE_DIR}." >&2
        exit 1
    }
    case "$origin_url" in
        "$REPO_URL"|git@github.com:Tkanchik/linka.git) ;;
        *)
            echo "[ошибка] ${SHARE_DIR} имеет другой origin: $origin_url" >&2
            exit 1
            ;;
    esac
    if [[ -n "$(git -C "${SHARE_DIR}" status --porcelain)" ]]; then
        echo "[ошибка] В ${SHARE_DIR} есть локальные изменения. Сохраните их перед обновлением." >&2
        exit 1
    fi
    if [[ "$(git -C "${SHARE_DIR}" symbolic-ref --quiet --short HEAD)" != main ]]; then
        echo "[ошибка] В ${SHARE_DIR} выбрана не ветка main. Переключитесь на main вручную." >&2
        exit 1
    fi
    git -C "${SHARE_DIR}" fetch origin main
    if ! git -C "${SHARE_DIR}" merge-base --is-ancestor HEAD origin/main; then
        echo "[ошибка] В ${SHARE_DIR} есть локальные коммиты или расходящаяся история. Обновите репозиторий вручную." >&2
        exit 1
    fi
    git -C "${SHARE_DIR}" merge --ff-only origin/main
fi

chmod +x "${SHARE_DIR}/linka"
ln -sfn "${SHARE_DIR}/linka" "${LINKA_SYMLINK}"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    export PATH="${BIN_DIR}:${PATH}"
fi

echo -e "\033[1;32m==>\033[0m \033[1mlinka успешно установлена в ${LINKA_SYMLINK}\033[0m"

if [[ ! -t 0 ]] && (: </dev/tty) 2>/dev/null; then
    exec < /dev/tty
fi

exec "${LINKA_SYMLINK}" "$@"
