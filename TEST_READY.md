# Test Readiness Report (`TEST_READY.md`)

## 1. Executive Summary
The opaque-box End-to-End (E2E) test suite for the `linka` Fedora installer and system configuration management has been designed, implemented, and verified in `/home/larp/.gemini/antigravity/scratch/linka_repo/tests/`.

The test harness uses rootless mock environments (mock `sudo`, `dnf`, `dnf5`, `rpm`, `systemctl`, `readlink`, `notify-send`) and executes safely on any Linux host.

All **44 test cases** across **Tiers 1–4** covering **Features F1–F12** execute cleanly, and the master test runner `tests/run_tests.sh` exits with code `0`.

---

## 2. Test Execution Results Summary

| Suite / Tier | Script Path | Tests Run | Passed | Failed | Status |
|---|---|---|---|---|---|
| **Tier 1**: Sanity, Package Lists & Conflicts | `tests/tier1_packages_audit.sh` | 11 | 11 | 0 | **PASS** |
| **Tier 2**: DNF4/DNF5 & COPR Management | `tests/tier2_dnf_copr.sh` | 8 | 8 | 0 | **PASS** |
| **Tier 3**: Compositors & SDDM Integration | `tests/tier3_compositors_sddm.sh` | 14 | 14 | 0 | **PASS** |
| **Tier 4**: systemd Services & Auto-Updates | `tests/tier4_services_auto_update.sh` | 11 | 11 | 0 | **PASS** |
| **Overall Master Suite** | `tests/run_tests.sh` | **44** | **44** | **0** | **PASS (100%)** |

---

## 3. Test Inventory by Feature (F1–F12)

### Tier 1: Sanity & Package Lists Audit (F1, F2, F12)
- `[F12] test_syntax_integrity_linka`: Validates `bash -n linka` and `bash -n install.sh` exit 0 without syntax errors.
- `[F1] test_fedora_required_pkgs_cliphist_excluded`: Verifies `cliphist` is excluded from `REQUIRED_PKGS` on Fedora.
- `[F1] test_fedora_optional_pkgs_cliphist_included`: Verifies `cliphist` is placed in `OPTIONAL_PKGS` on Fedora.
- `[F1] test_fedora_sddm_and_bootstrap_pkgs`: Verifies `SDDM_PKGS` and `BOOTSTRAP_PKGS` match official Fedora packages.
- `[F1] test_pkg_installed_virtual_provides`: Verifies `pkg_installed` resolves virtual provides (`wget2-wget` -> `wget`) and binary fallback on PATH.
- `[F2] test_multimedia_conflict_ffmpeg_installed`: Verifies `ffmpeg-free` is excluded when `ffmpeg` (RPM Fusion) is present.
- `[F2] test_multimedia_conflict_ffmpeg_libs_installed`: Verifies `ffmpeg-free` is excluded when `ffmpeg-libs` is present.
- `[F2] test_multimedia_clean_system_ffmpeg_free_included`: Verifies `ffmpeg-free` is installed on clean system.
- `[F2] test_power_daemon_conflict_tuned_ppd_installed`: Verifies `power-profiles-daemon` is skipped when `tuned-ppd` is installed.
- `[F2] test_power_daemon_clean_system_ppd_included`: Verifies `power-profiles-daemon` is installed when `tuned-ppd` is absent.
- `[F2] test_binary_handling_fdfind_symlink`: Verifies symlink `fdfind -> fd` is established when `fd` binary is missing.

### Tier 2: DNF4/DNF5 Compatibility & COPR Management (F3, F4, F5)
- `[F3] test_copr_plugin_dnf4_installs_plugins_core`: Verifies DNF4 environment installs `dnf-plugins-core`.
- `[F3] test_copr_plugin_dnf5_installs_dnf5_plugins`: Verifies DNF5 environment installs `dnf5-plugins`.
- `[F3] test_copr_plugin_already_present_skips_install`: Verifies early return when `dnf copr` is already operational.
- `[F4] test_copr_enable_non_interactive_has_dash_y`: Verifies `fedora_enable_copr` uses non-interactive `-y`.
- `[F4] test_quickshell_copr_enable_on_install`: Verifies `errornointernet/quickshell` is enabled non-interactively with `-y`.
- `[F5] test_copr_solopasha_hyprland_pre_enabled_for_optional_pkgs`: Verifies `solopasha/hyprland` COPR is pre-enabled before `OPTIONAL_PKGS` loop.
- `[F5] test_optional_pkgs_isolated_installation_with_skip_unavailable`: Verifies optional packages use `--skip-unavailable` and per-package isolation.
- `[F5] test_optional_pkgs_already_installed_skipped`: Verifies already-installed optional packages are skipped.

### Tier 3: Compositors & SDDM Display Manager Integration (F6, F7, F8, F9)
- `[F6] test_cli_argument_retention_install_compositors`: Verifies CLI arguments (`hyprland`, `niri`, `sway`) are preserved into `SELECTED_COMPOSITORS`.
- `[F6] test_compositor_saved_selection_preserved_over_running`: Verifies `SELECTED_COMPOSITORS_SAVED` is not overridden by active running desktop.
- `[F7] test_comp_atom_mapping`: Verifies `comp_atom` returns lowercase package names (`hyprland`, `niri`, `sway`).
- `[F7] test_is_compositor_installed_detection`: Verifies package and binary detection for compositors.
- `[F7] test_auto_install_missing_hyprland`: Verifies missing Hyprland triggers `solopasha/hyprland` COPR and package install.
- `[F7] test_auto_install_niri_base_repo`: Verifies Niri installs directly from base repo without COPR when available.
- `[F7] test_auto_install_niri_copr_fallback`: Verifies Niri enables `yalter/niri` COPR fallback when absent from base repo.
- `[F7] test_auto_install_missing_sway`: Verifies missing Sway triggers package installation.
- `[F8] test_ensure_sddm_package_installs_missing_qt6`: Verifies `ensure_sddm_package` checks all `SDDM_PKGS` and installs missing Qt6 components.
- `[F8] test_other_display_manager_conflict_gdm`: Verifies GDM conflict detection via `/etc/systemd/system/display-manager.service`.
- `[F8] test_other_display_manager_sddm_no_conflict`: Verifies SDDM is recognized without false conflict.
- `[F8] test_setup_sddm_skips_service_on_dm_conflict`: Verifies `sddm.service` activation is skipped when other DM is active.
- `[F9] test_setup_sddm_deploys_theme_and_config`: Verifies Material You theme deployment, `.linka-managed` marker, and drop-in config.
- `[F9] test_setup_sddm_unmanaged_theme_skipped`: Verifies unmanaged SDDM theme is not overwritten.

### Tier 4: systemd Services, Auto-Updates & Installer Bootstrap (F10, F11, F12)
- `[F10] test_setup_services_pipewire_and_networkmanager`: Verifies PipeWire stack and NetworkManager activation.
- `[F10] test_setup_services_easyeffects_guarded_when_missing`: Verifies `easyeffects.service` is skipped when unit file is absent.
- `[F10] test_setup_services_easyeffects_enabled_when_present`: Verifies `easyeffects.service` is enabled when unit file exists.
- `[F10] test_setup_services_power_profiles_daemon_enabled_when_present`: Verifies `power-profiles-daemon.service` is enabled when unit exists.
- `[F10] test_setup_services_tuned_service_activated`: Verifies `tuned.service` is activated when `tuned-ppd` is present.
- `[F11] test_auto_system_fedora_dnf4_check_update`: Verifies `check-update` is used (compatible with both DNF4 and DNF5).
- `[F11] test_auto_system_fedora_exit_code_0_up_to_date`: Verifies code 0 is treated as up to date.
- `[F11] test_auto_system_fedora_exit_code_100_notify`: Verifies code 100 triggers update notification.
- `[F11] test_auto_system_fedora_exit_code_100_apply`: Verifies code 100 triggers `AUTO_DNF_APPLY` unattended upgrade.
- `[F11] test_auto_system_fedora_other_exit_codes_handled`: Verifies non-zero/non-100 exit codes produce non-fatal warnings without crashing.
- `[F12] test_install_sh_bootstrap_integrity`: Verifies `install.sh` syntax and symlink deployment logic.

---

## 4. Verification Command
To reproduce the 100% passing test execution:

```bash
cd /home/larp/.gemini/antigravity/scratch/linka_repo
./tests/run_tests.sh
```

Expected output:
```
======================================================
                 FINAL TEST SUMMARY                   
======================================================
Total Suites Executed: 4
Passed Suites        : 4
Failed Suites        : 0
======================================================
RESULT: ALL TESTS PASSED (100% SUCCESS)
```
Exit code: `0`.
