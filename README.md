# linka

Скрипт для установки и обновления [Serpantinum](https://github.com/ilyamiro/serpantinum) на Gentoo и Fedora.

В апстриме Serpantinum рассчитан на Arch Linux. На Gentoo и Fedora его приходится собирать по частям: подключать оверлеи (Guru или COPR), искать пакеты с другими названиями, прописывать USE-флаги для PipeWire и Qt6 и руками следить за зависимостями композитора.

`linka` делает это сама: ставит пакеты через Portage или DNF, раскладывает конфиги под выбранный композитор и умеет проверять обновления в фоне.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/Tkanchik/linka/main/install.sh | bash
```

Скрипт скачает репозиторий в `~/.local/share/linka`, сделает симлинк в `~/.local/bin/linka` и откроет меню настройки.

## Использование

Если запустить `linka` без параметров, откроется меню: там можно выбрать композитор, посмотреть статус пакетов, включить тему SDDM или запустить обновление.

Для терминала есть прямые команды:

```bash
linka                  # интерактивное меню
linka update           # обновить шелл до свежего коммита
linka update --force   # принудительно перенакатить файлы текущей версии
linka kill             # остановить процессы шелла и демона
linka remove           # снести шелл и вернуть старые конфиги из бэкапа
```

Перед каждым обновлением `linka` сохраняет копию конфигов в `~/.config/serpantinum-backups/` (по умолчанию хранятся 5 последних копий).

### Фоновые обновления

Проверку обновлений можно повесить на таймер `systemd --user` (или запустить встроенным демоном на OpenRC):

```bash
# Включить автообновление (по умолчанию раз в 15 минут)
linka auto enable

# Обновлять шелл, но системные пакеты не трогать
linka auto enable --interval 30 --shell apply --system off

# Только присылать уведомление о новом коммите
linka auto enable --shell notify

# Статус таймера и последние строки лога
linka auto status

# Отключить
linka auto disable
```

## Поддерживаемые системы

- **Дистрибутивы:** Gentoo (systemd и OpenRC), Fedora
- **Композиторы:** Niri, Hyprland, Sway

## Лицензия

[GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE)
