import os
import sys
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional, Tuple, Union

# Константы путей
REPO_SLUG = os.environ.get("SERPANTINUM_SLUG", "ilyamiro/serpantinum")
DEFAULT_BRANCH = os.environ.get("SERPANTINUM_BRANCH", "master")
REPO_URL = f"https://github.com/{REPO_SLUG}.git"

TARGET_BASE = Path(os.environ.get("TARGET_BASE", Path.home() / ".local/share/serpantinum"))
BIN_DIR = Path.home() / ".local/bin"
CONFIG_DIR = Path(os.environ.get("QS_CONFIG_DIR", Path.home() / ".config/serpantinum"))
STATE_DIR = Path(os.environ.get("QS_STATE_DIR", Path.home() / ".local/state/serpantinum"))
CACHE_BASE = Path(os.environ.get("CACHE_BASE", Path.home() / "serpantinum"))
BACKUP_BASE = Path.home() / ".config/serpantinum-backups"

# Цвета терминала
USE_COLOR = sys.stdout.isatty()

class Colors:
    RESET = "\033[0m" if USE_COLOR else ""
    BOLD = "\033[1m" if USE_COLOR else ""
    DIM = "\033[2m" if USE_COLOR else ""
    RED = "\033[31m" if USE_COLOR else ""
    GREEN = "\033[32m" if USE_COLOR else ""
    YELLOW = "\033[33m" if USE_COLOR else ""
    BLUE = "\033[34m" if USE_COLOR else ""
    CYAN = "\033[36m" if USE_COLOR else ""

def log_info(msg: str):
    print(f"{Colors.CYAN}[инфо]{Colors.RESET} {msg}")

def log_ok(msg: str):
    print(f"{Colors.GREEN}[ ok ]{Colors.RESET} {msg}")

def log_warn(msg: str):
    print(f"{Colors.YELLOW}[вним]{Colors.RESET} {msg}")

def log_error(msg: str):
    print(f"{Colors.RED}[ошиб]{Colors.RESET} {msg}", file=sys.stderr)

def run_cmd(
    cmd: Union[List[str], str],
    check: bool = False,
    capture: bool = False,
    cwd: Optional[Union[str, Path]] = None,
    env: Optional[dict] = None,
    sudo: bool = False,
) -> Tuple[int, str, str]:
    """Безопасный запуск системных команд."""
    if isinstance(cmd, str):
        cmd_list = ["bash", "-c", cmd]
    else:
        cmd_list = list(cmd)

    if sudo and os.geteuid() != 0:
        cmd_list = ["sudo"] + cmd_list

    run_env = os.environ.copy()
    if env:
        run_env.update(env)

    try:
        proc = subprocess.run(
            cmd_list,
            cwd=str(cwd) if cwd else None,
            env=run_env,
            capture_output=capture,
            text=True,
            check=check,
        )
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""
        return proc.returncode, stdout.strip(), stderr.strip()
    except subprocess.CalledProcessError as e:
        return e.returncode, (e.stdout or "").strip(), (e.stderr or "").strip()
    except FileNotFoundError:
        return 127, "", f"Команда не найдена: {cmd_list[0]}"
    except Exception as e:
        return 1, "", str(e)
