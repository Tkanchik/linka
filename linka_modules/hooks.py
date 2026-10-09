import os
from pathlib import Path
from .common import CONFIG_DIR, TARGET_BASE, log_info, log_ok, log_warn, run_cmd

def run_post_update() -> bool:
    """Выполнение пользовательского post-update хука."""
    hook_file = CONFIG_DIR / "hooks/post_update.sh"
    if not hook_file.exists():
        return True

    if not os.access(hook_file, os.X_OK):
        hook_file.chmod(hook_file.stat().st_mode | 0o111)

    log_info(f"Запуск пользовательского хука: {hook_file}")
    env = {
        "TARGET_DIR": str(TARGET_BASE),
        "TARGET_BASE": str(TARGET_BASE),
        "CONFIG_DIR": str(CONFIG_DIR),
    }

    ret, out, err = run_cmd([str(hook_file)], env=env)
    if ret == 0:
        log_ok("Пользовательский хук успешно выполнен.")
        return True
    else:
        log_warn(f"Пользовательский хук завершился с кодом {ret}: {err or out}")
        return False
