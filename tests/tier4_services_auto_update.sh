#!/usr/bin/env bash
# ==============================================================================
# Tier 4 Test Suite: systemd Services, Auto-Updates & Sync (F10, F11, F12)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_framework.sh"

echo -e "${COLOR_BOLD}Starting Tier 4 Test Suite: systemd Services & Auto-Updates${COLOR_RESET}"

# ------------------------------------------------------------------------------
# Test 4.1 (F10): PipeWire stack and NetworkManager activation in setup_services
# ------------------------------------------------------------------------------
test_setup_services_pipewire_and_networkmanager() {
    source "$LINKA_SCRIPT"
    preflight

    setup_services

    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    local started_log="$MOCK_LOGS/systemctl_started.log"

    assert_file_exists "$enabled_log" "systemctl enabled log must exist"
    assert_file_contains "$enabled_log" "global=1 units=pipewire wireplumber pipewire-pulse" \
        "PipeWire stack must be enabled globally"
    assert_file_contains "$enabled_log" "NetworkManager.service" \
        "NetworkManager.service must be enabled"

    assert_file_exists "$started_log" "systemctl started log must exist"
    assert_file_contains "$started_log" "user=1 units=pipewire wireplumber pipewire-pulse" \
        "PipeWire stack must be started for the user"
}
run_test "test_setup_services_pipewire_and_networkmanager" test_setup_services_pipewire_and_networkmanager "F10"

# ------------------------------------------------------------------------------
# Test 4.2 (F10): easyeffects.service guarded when unit missing
# ------------------------------------------------------------------------------
test_setup_services_easyeffects_guarded_when_missing() {
    source "$LINKA_SCRIPT"
    preflight

    # User units list does NOT contain easyeffects.service
    export MOCK_SYSTEMD_USER_UNITS="pipewire.service wireplumber.service"

    setup_services

    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    assert_file_not_contains "$enabled_log" "easyeffects.service" \
        "easyeffects.service must not be enabled when unit is not found"
}
run_test "test_setup_services_easyeffects_guarded_when_missing" test_setup_services_easyeffects_guarded_when_missing "F10"

# ------------------------------------------------------------------------------
# Test 4.3 (F10): easyeffects.service enabled when unit present
# ------------------------------------------------------------------------------
test_setup_services_easyeffects_enabled_when_present() {
    source "$LINKA_SCRIPT"
    preflight

    # User units list contains easyeffects.service
    export MOCK_SYSTEMD_USER_UNITS="pipewire.service wireplumber.service easyeffects.service"

    setup_services

    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    assert_file_exists "$enabled_log" "systemctl enabled log must exist"
    assert_file_contains "$enabled_log" "user=1 global=0 units=easyeffects.service" \
        "easyeffects.service must be enabled when unit is present"
}
run_test "test_setup_services_easyeffects_enabled_when_present" test_setup_services_easyeffects_enabled_when_present "F10"

# ------------------------------------------------------------------------------
# Test 4.4 (F10): power-profiles-daemon.service guarded and enabled when present
# ------------------------------------------------------------------------------
test_setup_services_power_profiles_daemon_enabled_when_present() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_SYSTEMD_SYSTEM_UNITS="NetworkManager.service power-profiles-daemon.service"

    setup_services

    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    assert_file_exists "$enabled_log" "systemctl enabled log must exist"
    assert_file_contains "$enabled_log" "power-profiles-daemon.service" \
        "power-profiles-daemon.service must be enabled when unit is present"
}
run_test "test_setup_services_power_profiles_daemon_enabled_when_present" test_setup_services_power_profiles_daemon_enabled_when_present "F10"

# ------------------------------------------------------------------------------
# Test 4.5 (F10): tuned.service activated when tuned-ppd is installed and unit present
# ------------------------------------------------------------------------------
test_setup_services_tuned_service_activated() {
    source "$LINKA_SCRIPT"
    preflight

    # tuned.service present, power-profiles-daemon absent
    export MOCK_SYSTEMD_SYSTEM_UNITS="NetworkManager.service tuned.service"

    setup_services

    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    assert_file_exists "$enabled_log" "systemctl enabled log must exist"
    assert_file_contains "$enabled_log" "tuned.service" \
        "tuned.service must be enabled when present"
    assert_file_not_contains "$enabled_log" "power-profiles-daemon.service" \
        "power-profiles-daemon.service must not be enabled when absent"
}
run_test "test_setup_services_tuned_service_activated" test_setup_services_tuned_service_activated "F10"

# ------------------------------------------------------------------------------
# Test 4.6 (F11): auto_system_fedora uses check-update on DNF4 without failure
# ------------------------------------------------------------------------------
test_auto_system_fedora_dnf4_check_update() {
    source "$LINKA_SCRIPT"
    preflight

    # In DNF4 mode, check-upgrade would fail with exit code 1.
    # auto_system_fedora must use check-update which works in DNF4.
    export MOCK_DNF_VERSION="4"
    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=0

    local rc=0
    auto_system_fedora notify || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora should succeed on DNF4"

    local dnf_log="$MOCK_LOGS/dnf.log"
    assert_file_exists "$dnf_log" "dnf log must exist"
    assert_file_contains "$dnf_log" "check-update" "check-update must be used instead of check-upgrade"
    assert_file_not_contains "$dnf_log" "check-upgrade" "check-upgrade must not be called"
}
run_test "test_auto_system_fedora_dnf4_check_update" test_auto_system_fedora_dnf4_check_update "F11"

# ------------------------------------------------------------------------------
# Test 4.7 (F11): auto_system_fedora exit code 0 indicates up to date
# ------------------------------------------------------------------------------
test_auto_system_fedora_exit_code_0_up_to_date() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=0

    local rc=0
    auto_system_fedora notify || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora must return 0"

    # No update notifications should be sent
    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_not_exists "$notify_log" "No notification should be sent when system is up-to-date"

    # State timestamp should be updated
    assert_file_exists "$AUTO_CONF" "auto.conf state file must exist"
    assert_file_contains "$AUTO_CONF" "AUTO_LAST_SYSTEM=" "AUTO_LAST_SYSTEM timestamp must be updated"
}
run_test "test_auto_system_fedora_exit_code_0_up_to_date" test_auto_system_fedora_exit_code_0_up_to_date "F11"

# ------------------------------------------------------------------------------
# Test 4.8 (F11): auto_system_fedora exit code 100 in notify mode
# ------------------------------------------------------------------------------
test_auto_system_fedora_exit_code_100_notify() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=100

    local rc=0
    auto_system_fedora notify || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora must return 0"

    # Desktop notification must be dispatched
    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_exists "$notify_log" "Notification log must exist"
    assert_file_contains "$notify_log" "Обновления системы" "Notification about system updates must be sent"

    # Timestamp updated
    assert_file_exists "$AUTO_CONF" "auto.conf state file must exist"
    assert_file_contains "$AUTO_CONF" "AUTO_LAST_SYSTEM=" "AUTO_LAST_SYSTEM timestamp must be updated"
}
run_test "test_auto_system_fedora_exit_code_100_notify" test_auto_system_fedora_exit_code_100_notify "F11"

# ------------------------------------------------------------------------------
# Test 4.9 (F11): auto_system_fedora exit code 100 in apply mode
# ------------------------------------------------------------------------------
test_auto_system_fedora_exit_code_100_apply() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=100
    export MOCK_NEEDS_RESTARTING=0

    local rc=0
    auto_system_fedora apply || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora must return 0"

    # DNF upgrade command executed
    local upgrade_log="$MOCK_LOGS/dnf_upgrade.log"
    assert_file_exists "$upgrade_log" "upgrade log must exist"
    assert_file_contains "$upgrade_log" "UPGRADE:" "dnf upgrade must be executed"

    # Completion notification sent
    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_exists "$notify_log" "Notification log must exist"
    assert_file_contains "$notify_log" "Система обновлена" "System updated notification must be sent"
}
run_test "test_auto_system_fedora_exit_code_100_apply" test_auto_system_fedora_exit_code_100_apply "F11"

# ------------------------------------------------------------------------------
# Test 4.10 (F11): auto_system_fedora non-fatal warning on other exit codes
# ------------------------------------------------------------------------------
test_auto_system_fedora_other_exit_codes_handled() {
    source "$LINKA_SCRIPT"
    preflight

    # Simulate network error or repo metadata failure (exit code 1)
    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=1

    local rc=0
    auto_system_fedora notify || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora should handle exit code 1 gracefully without error"

    # No upgrade should take place
    local upgrade_log="$MOCK_LOGS/dnf_upgrade.log"
    assert_file_not_exists "$upgrade_log" "No upgrade should be performed on error"
}
run_test "test_auto_system_fedora_other_exit_codes_handled" test_auto_system_fedora_other_exit_codes_handled "F11"

# ------------------------------------------------------------------------------
# Test 4.11 (F12): install.sh bootstrap integrity and symlink verification
# ------------------------------------------------------------------------------
test_install_sh_bootstrap_integrity() {
    # Test install.sh syntax
    local rc=0
    bash -n "$REPO_ROOT/install.sh" >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "0" "install.sh syntax check must pass"

    # Verify symlink creation logic in install.sh
    assert_file_contains "$REPO_ROOT/install.sh" "ln -sf" "install.sh must create symlink"
    assert_file_contains "$REPO_ROOT/install.sh" "linka" "install.sh must target linka"
}
run_test "test_install_sh_bootstrap_integrity" test_install_sh_bootstrap_integrity "F12"

print_suite_summary "Tier 4: systemd Services & Auto-Updates"
