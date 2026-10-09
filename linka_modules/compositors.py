import shutil
from pathlib import Path
from .common import BACKUP_BASE, log_info, log_ok, log_warn

COMPOSITOR_DIRS = {
    "niri": Path.home() / ".config/niri",
    "hyprland": Path.home() / ".config/hypr",
    "sway": Path.home() / ".config/sway",
}

def deploy_compositor(repo_dir: Path, compositor: str = "niri", overwrite: bool = False) -> bool:
    """Развёртывание конфигурации выбранного композитора."""
    src = repo_dir / "compositors" / compositor
    dst = COMPOSITOR_DIRS.get(compositor)

    if not src.exists():
        log_warn(f"Каталог конфигурации композитора не найден: {src}")
        return False

    if not dst:
        log_warn(f"Неизвестный композитор: {compositor}")
        return False

    if dst.exists():
        if not overwrite:
            log_info(f"Конфигурация {compositor} уже существует в {dst}, пропускаем (используйте переустановку для перезаписи).")
            return True
        # Резервная копия перед перезаписью
        BACKUP_BASE.mkdir(parents=True, exist_ok=True)
        backup_path = BACKUP_BASE / f"{compositor}_backup"
        if backup_path.exists():
            shutil.rmtree(backup_path)
        shutil.copytree(dst, backup_path)
        log_info(f"Создан бэкап старой конфигурации: {backup_path}")

    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        target = dst / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)

    log_ok(f"Конфигурация {compositor} развёрнута в {dst}.")
    return True
