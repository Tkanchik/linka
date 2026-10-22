# linka

`linka` устанавливает и обновляет [Serpantinum](https://github.com/ilyamiro/serpantinum) на Gentoo и Fedora. На Gentoo `linka` подключает оверлеи, устанавливает пакеты через Portage и выставляет нужные USE-флаги.

Поддерживаются Niri, Hyprland, Sway и MangoWM. На Gentoo работают systemd и OpenRC.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/Tkanchik/linka/main/install.sh | bash
```

Нужен `git`. Установщик сохраняет `linka` в `~/.local/share/linka`, создаёт команду `~/.local/bin/linka` и открывает меню установки Serpantinum. При установке системных пакетов потребуется `sudo`.


## Как пользоваться

Без аргументов `linka` открывает меню. Там можно выбрать композитор, установить или обновить Serpantinum, посмотреть состояние пакетов и настроить тему SDDM.

| Команда | Действие |
| --- | --- |
| `linka install` | Установить Serpantinum; при повторном запуске обновить файлы, сохранив пользовательские конфиги. |
| `linka install mango` | Выбрать MangoWM для установки. |
| `linka reinstall` | Переустановить Serpantinum с резервной копией прежних файлов и конфигов. |
| `linka update` | Обновить Serpantinum до нового коммита. |
| `linka update --force` | Повторно развернуть файлы текущей версии. |
| `linka kill` | Остановить шелл и его процессы. |
| `linka remove` | Удалить Serpantinum после сохранения настроек. Сама `linka` остаётся установленной. |

## MangoWM

MangoWM можно выбрать в меню или командой `linka install mango`. Для конфигурации Serpantinum нужна версия 0.18 или новее. `linka` проверяет её перед развёртыванием и останавливается, если подходящая версия не установлена.

На Fedora `linka` при необходимости подключает репозиторий Terra. На Gentoo использует пакет `gui-wm/mangowm` из GURU. Если установленный снимок GURU устарел и в нём нет выпуска 0.18+, синхронизируйте оверлей и повторите установку.

Проверить установленный конфиг можно так:

```bash
mango -c ~/.config/mango/config.conf -p
```

## Конфиги и резервные копии

При обновлении `linka` сохраняет настройки Serpantinum в `~/.config/serpantinum-backups/`. При переустановке туда же перемещается прежний каталог `~/.local/share/serpantinum`. По умолчанию хранятся пять последних копий каждого типа; число можно изменить через `LINKA_BACKUP_KEEP`.

Перед заменой конфига композитора `linka` сохраняет его копию. Если резервную копию создать не удалось или файлы не скопировались, развёртывание прекращается с ошибкой. Конфиги, заданные симлинками, пропускаются: их целевые каталоги не меняются.

Для MangoWM первая установка и переустановка сохраняют существующий `~/.config/mango`, затем копируют конфиг Serpantinum. При обычном обновлении `config.conf` не перезаписывается, если он уже есть.

Если существует `~/.config/serpantinum/hooks/post_update.sh`, `linka` запускает его после развёртывания файлов. `linka remove` предварительно сохраняет настройки, а каталог пользовательских шрифтов `~/.local/share/fonts/IosevkaNerdFont` оставляет на месте.

## Фоновые обновления

`linka auto enable` включает проверку Serpantinum каждые 15 минут. Если доступен пользовательский таймер systemd, используется он; в остальных случаях работает демон с автозапуском через XDG. По умолчанию `linka` обновляет Serpantinum, но не обновляет системные пакеты.

```bash
linka auto enable
linka auto enable --shell notify
linka auto enable --interval 30 --shell apply --system off
linka auto enable --system apply --every-days 2
linka auto status
linka auto run
linka auto daemon
linka auto disable
```

`--shell notify` только сообщает о новом коммите. `linka auto daemon` запускает цикл в текущем терминале; это пригодится, если композитор не запускает приложения из XDG autostart. Для системных пакетов доступны режимы `--system notify` и `--system apply`. На Fedora уведомления о пакетах работают без правила `sudoers`; для применения обновлений оно потребуется. На Gentoo правило нужно для обоих режимов. При включении `linka` создаёт `/etc/sudoers.d/linka-auto` с доступом без пароля только к нужным командам `dnf` или `emerge`. `linka auto disable` удаляет это правило.

При разработке `linka` использовался ИИ.

## Лицензия

[AGPL-3.0](LICENSE)
