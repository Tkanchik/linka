# linka

> **Автономный установщик и менеджер обновлений Serpantinum для Gentoo и Fedora Linux.**

`linka` позволяет развернуть окружение [Serpantinum](https://github.com/ilyamiro/serpantinum) (на базе Quickshell и Wayland) на дистрибутивах **Gentoo** и **Fedora** одной командой, а также управлять его обновлениями и компонентами.

---

## ⚡ Быстрая установка

Вставьте команду в терминал:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Tkanchik/linka/main/install.sh)
```

*или через конвейер:*

```bash
curl -fsSL https://raw.githubusercontent.com/Tkanchik/linka/main/install.sh | bash
```

Скрипт автоматически:
1. Загрузит `linka` в `~/.local/bin/linka` и сделает исполняемой.
2. Проверит дистрибутив (Gentoo / Fedora) и окружение.
3. Откроет интерактивное TUI-меню установки с выбором композитора (Niri, Sway, Hyprland) и пакетов.

---

## 🚀 Возможности

- **Полная автоматизация зависимостей:** Установка необходимых ebuild-пакетов на Gentoo (через `emerge`) и пакетов на Fedora (через `dnf`).
- **Темы и шрифты:** Автоматическая установка шрифта Iosevka Nerd Font и темы SDDM Material You.
- **Менеджер жизненного цикла:**
  - `linka` — главное интерактивное меню.
  - `linka install` — чистая установка.
  - `linka update` — проверка и накат обновлений из апстрима Serpantinum.
  - `linka update --force` — принудительное обновление.
  - `linka auto enable` — включение фоновых автообновлений через `systemd --user`.
  - `linka kill` — корректная остановка всех процессов шелла.
  - `linka remove` — безопасное удаление.
- **Защита кастомизаций:** Поддержка хука `~/.config/serpantinum/hooks/post_update.sh` для восстановления ваших пользовательских виджетов и шаблонов после каждого обновления.

---

## 📋 Использование после установки

После установки утилита доступна напрямую из терминала:

```bash
# Открыть интерактивное меню управления
linka

# Обновить Serpantinum до последнего коммита
linka update

# Включить автоматические тихие обновления
linka auto enable
```

---

## 🔗 Ссылки и благодарности

- Оболочка **Serpantinum**: [ilyamiro/serpantinum](https://github.com/ilyamiro/serpantinum)
- Движок интерфейса: [Quickshell](https://quickshell.outfoxxed.me/)

## Лицензия

GNU Affero General Public License v3.0 (AGPL-3.0) — в соответствии с лицензией проекта Serpantinum.
