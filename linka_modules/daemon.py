import shutil
from pathlib import Path
from .common import BIN_DIR, log_info, log_ok, log_warn, run_cmd

SERVICE_TEMPLATE = """[Unit]
Description=linka: фоновое автообновление Serpantinum
After=network-online.target

[Service]
Type=oneshot
ExecStart={linka_path} auto run
Environment=PATH={bin_dir}:/usr/local/bin:/usr/bin:/bin
Nice=15
IOSchedulingClass=idle
KillMode=process
"""

TIMER_TEMPLATE = """[Unit]
Description=linka: таймер проверки обновлений Serpantinum

[Timer]
OnBootSec=10min
OnUnitActiveSec=20min
Persistent=true

[Install]
WantedBy=timers.target
"""

UNIT_DIR = Path.home() / ".config/systemd/user"

def enable_daemon() -> bool:
    """Включение службы и таймера автообновления."""
    UNIT_DIR.mkdir(parents=True, exist_ok=True)
    linka_path = shutil.which("linka") or str(BIN_DIR / "linka")

    service_file = UNIT_DIR / "linka-auto.service"
    timer_file = UNIT_DIR / "linka-auto.timer"

    service_file.write_text(SERVICE_TEMPLATE.format(linka_path=linka_path, bin_dir=BIN_DIR))
    timer_file.write_text(TIMER_TEMPLATE)

    run_cmd(["systemctl", "--user", "daemon-reload"])
    ret, _, _ = run_cmd(["systemctl", "--user", "enable", "--now", "linka-auto.timer"])

    if ret == 0:
        log_ok("Автообновления успешно включены (linka-auto.timer активен).")
        return True
    else:
        log_warn("Не удалось активировать linka-auto.timer.")
        return False

def disable_daemon() -> bool:
    """Отключение службы и таймера автообновления."""
    run_cmd(["systemctl", "--user", "disable", "--now", "linka-auto.timer"])
    run_cmd(["systemctl", "--user", "stop", "linka-auto.service"])
    log_ok("Автообновления отключены.")
    return True

def daemon_status():
    """Проверка статуса таймера."""
    ret, out, _ = run_cmd(["systemctl", "--user", "status", "linka-auto.timer"], capture=True)
    print(out if out else "Служба не найдена.")
