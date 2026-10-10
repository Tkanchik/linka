import os
import shutil
from pathlib import Path
from typing import Optional, Tuple
from .common import (
    REPO_URL,
    DEFAULT_BRANCH,
    CACHE_BASE,
    TARGET_BASE,
    log_info,
    log_ok,
    log_warn,
    log_error,
    run_cmd,
)
from .deploy import deploy_core, deploy_user_configs, deploy_fonts
from .hooks import run_post_update

def ensure_repo(branch: str = DEFAULT_BRANCH) -> Optional[Path]:
    """Клонирование или обновление локального git-кэша репозитория."""
    if not shutil.which("git"):
        log_error("git не установлен в системе.")
        return None

    CACHE_BASE.parent.mkdir(parents=True, exist_ok=True)

    if not (CACHE_BASE / ".git").exists():
        log_info(f"Клонирование репозитория Serpantinum ({REPO_URL})...")
        ret, _, err = run_cmd(["git", "clone", "-b", branch, REPO_URL, str(CACHE_BASE)])
        if ret != 0:
            log_error(f"Не удалось склонировать репозиторий: {err}")
            return None
    else:
        log_info(f"Синхронизация локального кэша в {CACHE_BASE}...")
        run_cmd(["git", "remote", "set-url", "origin", REPO_URL], cwd=CACHE_BASE)
        run_cmd(["git", "fetch", "origin", branch], cwd=CACHE_BASE)
        run_cmd(["git", "checkout", branch], cwd=CACHE_BASE)
        run_cmd(["git", "reset", "--hard", f"origin/{branch}"], cwd=CACHE_BASE)

    return CACHE_BASE

def get_installed_commit() -> str:
    """Определение текущего коммита установленной версии."""
    state_file = TARGET_BASE / ".serpantinum-commit"
    if state_file.exists():
        return state_file.read_text().strip()
    return ""

def get_repo_commit(repo_dir: Path) -> str:
    """Получение текущего коммита из git-репозитория."""
    ret, out, _ = run_cmd(["git", "rev-parse", "HEAD"], cwd=repo_dir, capture=True)
    return out.strip() if ret == 0 else ""

def perform_update(force: bool = False, branch: str = DEFAULT_BRANCH) -> bool:
    """Основной процесс проверки и наката обновлений."""
    repo = ensure_repo(branch=branch)
    if not repo:
        return False

    current_commit = get_installed_commit()
    target_commit = get_repo_commit(repo)

    if not force and current_commit and current_commit == target_commit:
        log_ok(f"Serpantinum уже обновлён до актуальной версии ({current_commit[:7]}).")
        return True

    log_info(f"Обновление: {current_commit[:7] if current_commit else 'неизвестно'} → {target_commit[:7]}")

    # 1. Развёртывание ядра
    if not deploy_core(repo):
        return False

    # 2. Обновление шрифтов
    deploy_fonts(repo)

    # 3. Сохранение текущего коммита
    try:
        (TARGET_BASE / ".serpantinum-commit").write_text(target_commit)
    except Exception:
        pass

    # 4. Запуск post-update хука
    run_post_update()

    # 5. Перезапуск шелла при необходимости
    restart_shell_if_running()

    log_ok(f"Обновление до {target_commit[:7]} успешно завершено.")
    return True

def restart_shell_if_running():
    """Перезапуск Quickshell, если он запущен."""
    ret, out, _ = run_cmd(["pgrep", "-f", "quickshell"], capture=True)
    if ret != 0:
        ret, out, _ = run_cmd(["pgrep", "-f", "bin/serpantinumd"], capture=True)
    if ret == 0:
        log_info("Перезапуск Quickshell...")
        run_cmd(["serpantinumd", "stop"])
        time.sleep(1)
        if shutil.which("systemd-run") and run_cmd(["systemctl", "--user", "list-units"], capture=True)[0] == 0:
            env_vars = ["WAYLAND_DISPLAY", "DISPLAY", "XDG_RUNTIME_DIR", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "PATH"]
            cmd = ["systemd-run", "--user", "--collect", "--slice=app.slice"]
            import os
            for var in env_vars:
                val = os.environ.get(var)
                if val:
                    cmd.append(f"--setenv={var}={val}")
            cmd.extend(["serpantinumd", "start"])
            run_cmd(cmd)
        else:
            import subprocess
            subprocess.Popen(
                ["serpantinumd", "start"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
