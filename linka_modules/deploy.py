import os
import shutil
from pathlib import Path
from typing import Optional
from .common import (
    TARGET_BASE,
    BIN_DIR,
    CONFIG_DIR,
    BACKUP_BASE,
    log_info,
    log_ok,
    log_warn,
    log_error,
    run_cmd,
)

def copy_tree(src: Path, dst: Path, overwrite: bool = True):
    """Рекурсивное копирование дерева файлов."""
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        target = dst / item.name
        if item.is_dir():
            copy_tree(item, target, overwrite=overwrite)
        else:
            if overwrite or not target.exists():
                shutil.copy2(item, target)

def deploy_core(repo_dir: Path) -> bool:
    """Развёртывание ядра Serpantinum (bin/ и src/) в TARGET_BASE."""
    log_info(f"Развёртывание Serpantinum в {TARGET_BASE}...")

    src_dir = repo_dir / "src"
    bin_dir = repo_dir / "bin"
    version_file = repo_dir / "version.txt"

    if not src_dir.exists():
        log_error(f"Каталог src не найден в {repo_dir}")
        return False

    TARGET_BASE.mkdir(parents=True, exist_ok=True)

    # 1. Копирование src/
    target_src = TARGET_BASE / "src"
    copy_tree(src_dir, target_src)

    # 2. Копирование bin/
    if bin_dir.exists():
        target_bin = TARGET_BASE / "bin"
        copy_tree(bin_dir, target_bin)

    # 3. Копирование version.txt (важно для корректной работы Updater.qml!)
    if version_file.exists():
        shutil.copy2(version_file, TARGET_BASE / "version.txt")
    elif (src_dir / "version.txt").exists():
        try:
            content = (src_dir / "version.txt").read_text()
            (TARGET_BASE / "version.txt").write_text(content)
        except Exception:
            pass

    # 4. Установка прав на исполнение для всех скриптов
    for p in TARGET_BASE.glob("**/*.sh"):
        p.chmod(p.stat().st_mode | 0o111)
    if (TARGET_BASE / "bin").exists():
        for p in (TARGET_BASE / "bin").iterdir():
            p.chmod(p.stat().st_mode | 0o111)

    # 5. Создание симлинков в ~/.local/bin
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    for script_name in ["serpantinum", "serpantinumd"]:
        source_script = TARGET_BASE / "bin" / script_name
        link_dest = BIN_DIR / script_name
        if source_script.exists():
            if link_dest.is_symlink() or link_dest.exists():
                link_dest.unlink()
            link_dest.symlink_to(source_script)
            log_ok(f"Симлинк: {link_dest} -> {source_script}")

    log_ok("Ядро Serpantinum успешно развёрнуто.")
    return True

def deploy_user_configs(repo_dir: Path, is_update: bool = False):
    """Развёртывание пользовательских конфигов (kitty, cava, fastfetch)."""
    configs = ["kitty", "cava", "fastfetch"]
    for c in configs:
        src = repo_dir / "config" / c
        tgt = Path.home() / ".config" / c

        if not src.exists():
            continue

        if not is_update or not tgt.exists():
            # Если файл существует, делаем бэкап
            if tgt.exists():
                BACKUP_BASE.mkdir(parents=True, exist_ok=True)
                backup_dest = BACKUP_BASE / f"{c}_backup"
                if backup_dest.exists():
                    shutil.rmtree(backup_dest)
                shutil.copytree(tgt, backup_dest)

            if src.is_dir():
                copy_tree(src, tgt)
            else:
                tgt.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, tgt)
            log_ok(f"Установлен конфиг: ~/.config/{c}")

def deploy_fonts(repo_dir: Path):
    """Проверка и установка шрифтов Iosevka Nerd Font."""
    font_user_dir = Path.home() / ".local/share/fonts/IosevkaNerdFont"
    if font_user_dir.exists() and any(font_user_dir.glob("*.ttf")):
        return

    log_info("Установка шрифтов Iosevka Nerd Font...")
    font_user_dir.mkdir(parents=True, exist_ok=True)
    # Если в репозитории есть готовые шрифты или ссылки
    font_url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip"
    zip_path = Path("/tmp/Iosevka.zip")
    ret, _, _ = run_cmd(["curl", "-fsSL", font_url, "-o", str(zip_path)])
    if ret == 0 and zip_path.exists():
        run_cmd(["unzip", "-o", "-q", str(zip_path), "-d", str(font_user_dir)])
        zip_path.unlink(missing_ok=True)
        run_cmd(["fc-cache", "-f"])
        log_ok("Шрифты Iosevka Nerd Font установлены.")

def deploy_sddm_theme(repo_dir: Path, enable: bool = False):
    """Установка темы SDDM Material You."""
    if not enable:
        return

    sddm_src = repo_dir / "src/assets/sddm/material-you"
    sddm_target = Path("/usr/share/sddm/themes/material-you")

    if sddm_src.exists():
        log_info("Установка темы SDDM Material You...")
        run_cmd(f"mkdir -p {sddm_target} && cp -a {sddm_src}/. {sddm_target}/", sudo=True)
        # Настройка sddm.conf.d
        conf_d = Path("/etc/sddm.conf.d")
        run_cmd(f"mkdir -p {conf_d}", sudo=True)
        conf_content = "[Theme]\nCurrent=material-you\n"
        run_cmd(f"echo '{conf_content}' | sudo tee {conf_d}/linka-serpantinum.conf >/dev/null")
        log_ok("Тема SDDM успешно настроена.")
