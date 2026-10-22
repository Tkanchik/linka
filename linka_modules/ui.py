import sys
import argparse
from pathlib import Path
from .common import Colors, log_info, log_ok, log_warn, log_error, run_cmd
from .distro import detect_distro
from .deps import check_and_install_deps
from .deploy import deploy_core, deploy_user_configs, deploy_fonts, deploy_sddm_theme
from .compositors import deploy_compositor
from .updater import ensure_repo, perform_update, get_repo_commit
from .daemon import enable_daemon, disable_daemon, daemon_status
from .hooks import run_post_update

def flow_install(reinstall: bool = False, compositor: str = "niri", sddm: bool = False):
    distro = detect_distro()
    if not distro:
        log_warn("Не удалось точно определить дистрибутив (ожидается Gentoo или Fedora). Продолжаем...")
    else:
        log_info(f"Обнаружен дистрибутив: {distro.name.capitalize()}")
        if not check_and_install_deps(distro, compositor):
            log_warn("Установка некоторых зависимостей завершилась с предупреждениями.")

    repo = ensure_repo()
    if not repo:
        log_error("Не удалось получить репозиторий Serpantinum.")
        return False

    if not deploy_core(repo):
        return False

    deploy_fonts(repo)

    deploy_compositor(repo, compositor=compositor, overwrite=reinstall)

    deploy_user_configs(repo, is_update=False)

    if sddm:
        deploy_sddm_theme(repo, enable=True)

    commit = get_repo_commit(repo)
    try:
        from .common import TARGET_BASE
        (TARGET_BASE / ".serpantinum-commit").write_text(commit)
    except Exception:
        pass

    run_post_update()

    log_ok("Установка Serpantinum успешно завершена!")
    print(f"\nДля запуска выполните: {Colors.BOLD}serpantinumd start{Colors.RESET}")
    return True

def flow_kill():
    log_info("Остановка процессов Serpantinum и Quickshell...")
    run_cmd(["pkill", "-TERM", "-f", "focus_daemon.py"])
    run_cmd(["pkill", "-TERM", "-x", "quickshell"])
    log_ok("Процессы остановлены.")

def flow_remove():
    from .common import TARGET_BASE, BIN_DIR
    confirm = input("Вы уверены, что хотите удалить Serpantinum? (y/N): ").strip().lower()
    if confirm not in ("y", "yes", "да"):
        print("Отмена.")
        return

    flow_kill()
    if TARGET_BASE.exists():
        import shutil
        shutil.rmtree(TARGET_BASE)
        log_ok(f"Удалён каталог {TARGET_BASE}")

    for script in ["serpantinum", "serpantinumd"]:
        p = BIN_DIR / script
        if p.exists() or p.is_symlink():
            p.unlink()

    log_ok("Serpantinum удалён из системы.")

def interactive_menu():
    while True:
        print(f"\n{Colors.BOLD}linka — Установщик и менеджер Serpantinum{Colors.RESET}")
        print("─" * 45)
        print("1. Установка Serpantinum")
        print("2. Переустановка (с перезаписью конфигов)")
        print("3. Проверить и применить обновления")
        print("4. Автоматические обновления (systemd timer)")
        print("5. Остановить шелл (linka kill)")
        print("6. Удалить Serpantinum")
        print("0. Выход")
        print("─" * 45)

        try:
            choice = input(f"{Colors.CYAN}Выберите пункт [0-6]: {Colors.RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nВыход.")
            break

        if choice == "1":
            comp = input("Композитор [niri/hyprland/sway] (по умолчанию: niri): ").strip().lower() or "niri"
            flow_install(reinstall=False, compositor=comp)
        elif choice == "2":
            comp = input("Композитор [niri/hyprland/sway] (по умолчанию: niri): ").strip().lower() or "niri"
            flow_install(reinstall=True, compositor=comp)
        elif choice == "3":
            perform_update(force=False)
        elif choice == "4":
            sub = input("Автообновления: 1 - включить, 2 - отключить, 3 - статус: ").strip()
            if sub == "1":
                enable_daemon()
            elif sub == "2":
                disable_daemon()
            elif sub == "3":
                daemon_status()
        elif choice == "5":
            flow_kill()
        elif choice == "6":
            flow_remove()
        elif choice in ("0", "q", "exit"):
            break
        else:
            print("Неверный выбор.")

def main():
    parser = argparse.ArgumentParser(
        prog="linka",
        description="Автономный установщик и менеджер обновлений Serpantinum для Gentoo и Fedora Linux.",
    )
    subparsers = parser.add_subparsers(dest="command")

    p_install = subparsers.add_parser("install", help="Чистая установка Serpantinum")
    p_install.add_argument("--compositor", default="niri", choices=["niri", "hyprland", "sway"], help="Выбор композитора")
    p_install.add_argument("--sddm", action="store_true", help="Установить тему SDDM")

    p_reinstall = subparsers.add_parser("reinstall", help="Переустановка с обновлением конфигов")
    p_reinstall.add_argument("--compositor", default="niri", choices=["niri", "hyprland", "sway"], help="Выбор композитора")

    p_update = subparsers.add_parser("update", help="Обновление Serpantinum")
    p_update.add_argument("-f", "--force", action="store_true", help="Принудительное обновление")
    p_update.add_argument("--branch", default="master", help="Ветка репозитория")

    p_auto = subparsers.add_parser("auto", help="Управление службой автообновлений")
    p_auto.add_argument("action", choices=["enable", "disable", "status", "run"], help="Действие со службой")

    subparsers.add_parser("kill", help="Остановить все процессы шелла")

    subparsers.add_parser("remove", help="Удалить Serpantinum")

    args = parser.parse_args()

    if not args.command:
        if sys.stdin.isatty():
            interactive_menu()
        else:
            parser.print_help()
        return

    if args.command == "install":
        flow_install(reinstall=False, compositor=args.compositor, sddm=args.sddm)
    elif args.command == "reinstall":
        flow_install(reinstall=True, compositor=args.compositor)
    elif args.command == "update":
        perform_update(force=args.force, branch=args.branch)
    elif args.command == "auto":
        if args.action == "enable":
            enable_daemon()
        elif args.action == "disable":
            disable_daemon()
        elif args.action == "status":
            daemon_status()
        elif args.action == "run":
            perform_update(force=False)
    elif args.command == "kill":
        flow_kill()
    elif args.command == "remove":
        flow_remove()
