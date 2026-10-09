from typing import List, Dict
from .common import log_info, log_ok, log_warn, log_error
from .distro import DistroManager, GentooManager, FedoraManager

# Списки базовых зависимостей
GENTOO_BASE_PKGS = [
    "gui-apps/quickshell",
    "sys-apps/file",
    "sys-process/psmisc",
    "media-video/ffmpeg",
    "sys-apps/fastfetch",
    "x11-misc/cliphist",
    "gui-apps/wl-clipboard",
    "media-fonts/iosevka-nerd-font",
    "x11-misc/matugen",
    "app-arch/unzip",
    "dev-python/websockets",
    "dev-python/jeepney",
    "dev-qt/qtwebsockets",
]

FEDORA_BASE_PKGS = [
    "file",
    "psmisc",
    "ffmpeg-free",
    "fastfetch",
    "cliphist",
    "wl-clipboard",
    "unzip",
    "python3-websockets",
    "python3-jeepney",
    "qt6-qtwebsockets",
]

COMPOSITOR_PKGS: Dict[str, Dict[str, str]] = {
    "gentoo": {
        "niri": "gui-wm/niri",
        "hyprland": "gui-wm/hyprland",
        "sway": "gui-wm/sway",
    },
    "fedora": {
        "niri": "niri",
        "hyprland": "hyprland",
        "sway": "sway",
    },
}

def get_required_pkgs(distro: DistroManager, compositor: str = "niri") -> List[str]:
    if isinstance(distro, GentooManager):
        pkgs = list(GENTOO_BASE_PKGS)
        comp_pkg = COMPOSITOR_PKGS["gentoo"].get(compositor)
        if comp_pkg:
            pkgs.append(comp_pkg)
        return pkgs
    elif isinstance(distro, FedoraManager):
        pkgs = list(FEDORA_BASE_PKGS)
        comp_pkg = COMPOSITOR_PKGS["fedora"].get(compositor)
        if comp_pkg:
            pkgs.append(comp_pkg)
        return pkgs
    return []

def check_and_install_deps(distro: DistroManager, compositor: str = "niri") -> bool:
    """Проверка и установка недостающих пакетов."""
    required = get_required_pkgs(distro, compositor)
    if not required:
        log_warn("Не удалось определить пакеты для вашего дистрибутива.")
        return True

    missing = []
    log_info("Проверка установленных зависимостей...")
    for pkg in required:
        if not distro.is_pkg_installed(pkg):
            missing.append(pkg)

    if not missing:
        log_ok("Все системные зависимости установлены.")
        return True

    log_warn(f"Необходимо установить пакеты ({len(missing)} шт.): {', '.join(missing)}")
    return distro.install_packages(missing)
