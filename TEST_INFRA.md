# linka E2E Test Infrastructure Specification (`TEST_INFRA.md`)

## 1. Overview
This document specifies the architectural design, directory structure, mock execution environment, and tier taxonomy for the opaque-box End-to-End (E2E) test suite of the `linka` installer on Fedora Linux.

The test infrastructure is designed to execute safely, hermetically, and rootlessly on **any Linux host** without modifying host system packages, repositories, `/etc` configuration files, or user environments.

---

## 2. Directory Layout

```
/home/larp/.gemini/antigravity/scratch/linka_repo/tests/
├── run_tests.sh                    # Master test runner (returns exit code 0 when all tests pass)
├── lib/
│   └── test_framework.sh           # Core test harness: assertions, test isolation, logging, reporting
├── mock_bin/                       # Isolated mock CLI binary stubs (prepended to PATH)
│   ├── sudo                        # Intercepts sudo commands, remaps /etc & /usr to sandbox, logs calls
│   ├── dnf                         # Emulates DNF4/DNF5 subcommands (copr, check-update, info, install, upgrade)
│   ├── dnf5                        # Symlink to dnf, forces DNF5 mode
│   ├── rpm                         # Emulates RPM queries (-q) and virtual provides (--whatprovides)
│   ├── systemctl                   # Emulates systemd global/user services, list-unit-files, enable, start
│   ├── readlink                    # Intercepts /etc/systemd/system/display-manager.service checks
│   ├── quickshell                  # Emulates quickshell binary and --version reporting
│   └── notify-send                 # Emulates desktop notification delivery, captures alert logs
├── tier1_packages_audit.sh         # Tier 1 tests: Sanity, package lists, conflicts & syntax (F1, F2, F12)
├── tier2_dnf_copr.sh               # Tier 2 tests: DNF4/DNF5 compatibility & COPR management (F3, F4, F5)
├── tier3_compositors_sddm.sh       # Tier 3 tests: Compositors (Hyprland, Niri, Sway) & SDDM (F6, F7, F8, F9)
└── tier4_services_auto_update.sh   # Tier 4 tests: systemd units & background auto-updates (F10, F11, F12)
```

---

## 3. Mock Environments Architecture

### 3.1 Mock `sudo` & Sandbox Path Remapping
- **Path**: `tests/mock_bin/sudo`
- **Behavior**:
  - Handles `sudo -v`, `sudo -n -v`, `sudo -n -k -l` without password prompts or root requirements.
  - Automatically redirects modifications targeting root-owned directories (`/etc/*`, `/usr/*`) into an isolated test sandbox `$MOCK_ROOT/etc/*` and `$MOCK_ROOT/usr/*`.
  - Supports standard file manipulation commands (`mkdir`, `cp`, `touch`, `chmod`, `tee`, `ln`, `rm`, `sed`).
  - Appends verbatim invocation arguments to `$MOCK_LOGS/sudo.log`.

### 3.2 Mock `dnf` & `dnf5`
- **Path**: `tests/mock_bin/dnf`, `tests/mock_bin/dnf5`
- **Modes**: Controlled via `$MOCK_DNF_VERSION` (`4` for classic DNF4, `5` for modern DNF5).
- **Subcommands Emulated**:
  - `--version`: Emulates DNF 4.19.2 or DNF 5.2.7.0.
  - `copr --help`: Verifies plugin presence using state flag `$MOCK_DNF_STATE/copr_plugin_active`.
  - `copr enable -y <repo>`: Confirms non-interactive `-y` flag; records to `$MOCK_LOGS/dnf_copr.log`.
  - `info <pkg>`: Simulates package presence against `$MOCK_DNF_AVAILABLE_PKGS`.
  - `install -y [--skip-unavailable] <pkgs...>`: Logs packages to `$MOCK_LOGS/dnf_install.log`; updates COPR plugin state when installing `dnf-plugins-core` (DNF4) or `dnf5-plugins` (DNF5).
  - `check-update`: Returns exit code configured by `$MOCK_DNF_CHECK_UPDATE_EXIT_CODE` (0 = no updates, 100 = updates pending).
  - `check-upgrade`: In DNF4 mode, exits with code 1 (`No such command: check-upgrade`); in DNF5 mode, returns `$MOCK_DNF_CHECK_UPDATE_EXIT_CODE`.
  - `upgrade -y`: Logs upgrade requests to `$MOCK_LOGS/dnf_upgrade.log`.
  - `needs-restarting -r`: Emulates reboot detection based on `$MOCK_NEEDS_RESTARTING`.

### 3.3 Mock `rpm`
- **Path**: `tests/mock_bin/rpm`
- **Subcommands Emulated**:
  - `rpm -q <pkg>`: Verifies whether package is listed in `$MOCK_RPM_INSTALLED_PKGS`.
  - `rpm -q --whatprovides <provide>`: Resolves virtual provides mapped in `$MOCK_RPM_PROVIDES` (e.g. `wget:wget2-wget`).
  - Logs all calls to `$MOCK_LOGS/rpm.log`.

### 3.4 Mock `systemctl`
- **Path**: `tests/mock_bin/systemctl`
- **Subcommands Emulated**:
  - `list-unit-files [--user] <service>`: Probes `$MOCK_SYSTEMD_USER_UNITS` or `$MOCK_SYSTEMD_SYSTEM_UNITS`.
  - `enable [--now] [--global] <services...>`: Records enabled units to `$MOCK_LOGS/systemctl_enabled.log`.
  - `start <services...>`: Records started units to `$MOCK_LOGS/systemctl_started.log`.

### 3.5 Mock `readlink`
- **Path**: `tests/mock_bin/readlink`
- **Behavior**: Intercepts `/etc/systemd/system/display-manager.service` queries and returns the target configured by `$MOCK_DM_LINK` (e.g. `/usr/lib/systemd/system/gdm.service` vs `/usr/lib/systemd/system/sddm.service`). Passes all other queries through to `/usr/bin/readlink`.

### 3.6 Mock `notify-send` & `quickshell`
- **Path**: `tests/mock_bin/notify-send`: Records notification messages to `$MOCK_LOGS/notify.log`.
- **Path**: `tests/mock_bin/quickshell`: Outputs configured version `${MOCK_QUICKSHELL_VERSION:-0.2.1}` on `--version`.

---

## 4. Test Tiers & Feature Mapping

| Tier | Suite Script | Features Covered | Description |
|---|---|---|---|
| **Tier 1** | `tests/tier1_packages_audit.sh` | **F1, F2, F12** | Validates Bash syntax (`bash -n`), Fedora official package lists, exclusion of `cliphist` from `REQUIRED_PKGS`, placement of `cliphist` in `OPTIONAL_PKGS`, virtual provides (`wget2-wget` -> `wget`), conflict skipping for multimedia (`ffmpeg-free` vs `ffmpeg`/`ffmpeg-libs`) and power management (`power-profiles-daemon` vs `tuned-ppd`), and `fdfind` to `fd` symlink creation. |
| **Tier 2** | `tests/tier2_dnf_copr.sh` | **F3, F4, F5** | Validates version-aware COPR plugin installation (`dnf-plugins-core` on DNF4, `dnf5-plugins` on DNF5), non-interactive COPR enablement with `-y`, pre-enablement of `solopasha/hyprland` before optional package loop, and isolated installation of `OPTIONAL_PKGS` with `--skip-unavailable`. |
| **Tier 3** | `tests/tier3_compositors_sddm.sh` | **F6, F7, F8, F9** | Validates CLI argument retention (`linka install <comp>`), preservation of saved compositor choice (`SELECTED_COMPOSITORS_SAVED`) across active sessions, automatic package resolution and installation (`comp_atom`, Hyprland, Niri base/COPR fallback, Sway), SDDM package dependency verification (`SDDM_PKGS`), display manager conflict prevention (GDM/LightDM), Material You theme deployment, and drop-in configuration. |
| **Tier 4** | `tests/tier4_services_auto_update.sh` | **F10, F11, F12** | Validates systemd service activation (PipeWire stack, NetworkManager), unit existence guards (`easyeffects.service`, `power-profiles-daemon.service`, `tuned.service`), DNF `check-update` return code semantics (0 = up to date, 100 = updates available, other = non-fatal warning), `AUTO_DNF_APPLY` unattended upgrades, and `install.sh` bootstrap integrity. |

---

## 5. How to Run the Tests

### 5.1 Run Entire Test Suite
```bash
./tests/run_tests.sh
```

### 5.2 Run a Specific Tier
```bash
./tests/run_tests.sh --tier 1    # Run Tier 1 only
./tests/run_tests.sh --tier 2    # Run Tier 2 only
./tests/run_tests.sh --tier 3    # Run Tier 3 only
./tests/run_tests.sh --tier 4    # Run Tier 4 only
```

### 5.3 Run an Individual Test Suite Directly
```bash
./tests/tier1_packages_audit.sh
./tests/tier2_dnf_copr.sh
./tests/tier3_compositors_sddm.sh
./tests/tier4_services_auto_update.sh
```

---

## 6. Exit Code Conventions
- `0`: All executed tests passed successfully.
- `1`: One or more test assertions failed.
