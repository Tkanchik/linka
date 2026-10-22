import shutil
from pathlib import Path
from typing import List, Optional
from .common import log_info, log_ok, log_warn, log_error, run_cmd

class DistroManager:
    name: str = "unknown"

    def is_pkg_installed(self, pkg: str) -> bool:
        raise NotImplementedError

    def install_packages(self, pkgs: List[str]) -> bool:
        raise NotImplementedError

    def update_system(self) -> bool:
        raise NotImplementedError


class GentooManager(DistroManager):
    name = "gentoo"

    def is_pkg_installed(self, pkg: str) -> bool:
        if shutil.which("portageq"):
            ret, _, _ = run_cmd(["portageq", "has_version", "/", pkg], capture=True)
            return ret == 0
        if shutil.which("qlist"):
            ret, out, _ = run_cmd(["qlist", "-I", pkg], capture=True)
            return ret == 0 and bool(out)
        return False

    def install_packages(self, pkgs: List[str]) -> bool:
        if not pkgs:
            return True
        log_info(f"Gentoo: установка пакетов через emerge: {' '.join(pkgs)}")
        cmd = ["emerge", "--ask=n", "--verbose", "--noreplace"] + pkgs
        ret, _, _ = run_cmd(cmd, sudo=True)
        return ret == 0

    def update_system(self) -> bool:
        log_info("Gentoo: синхронизация репозиториев (emerge --sync)...")
        ret, _, _ = run_cmd(["emerge", "--sync"], sudo=True)
        return ret == 0


class FedoraManager(DistroManager):
    name = "fedora"

    def is_pkg_installed(self, pkg: str) -> bool:
        ret, _, _ = run_cmd(["rpm", "-q", pkg], capture=True)
        return ret == 0

    def install_packages(self, pkgs: List[str]) -> bool:
        if not pkgs:
            return True
        log_info(f"Fedora: установка пакетов через dnf: {' '.join(pkgs)}")
        cmd = ["dnf", "install", "-y"] + pkgs
        ret, _, _ = run_cmd(cmd, sudo=True)
        return ret == 0

    def update_system(self) -> bool:
        log_info("Fedora: обновление кэша dnf...")
        ret, _, _ = run_cmd(["dnf", "check-update", "-y"], sudo=True)
        return ret in (0, 100)


def detect_distro() -> Optional[DistroManager]:
    os_release = Path("/etc/os-release")
    if not os_release.exists():
        return None

    data = {}
    with open(os_release, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip().strip('"').strip("'").lower()

    dist_id = data.get("ID", "")
    id_like = data.get("ID_LIKE", "")

    if "gentoo" in dist_id or "gentoo" in id_like:
        return GentooManager()
    if "fedora" in dist_id or "fedora" in id_like:
        return FedoraManager()

    return None
