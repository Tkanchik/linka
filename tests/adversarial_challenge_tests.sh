#!/usr/bin/env bash
# ==============================================================================
# Adversarial Challenge Test Suite: Compositors, SDDM Conflicts & Auto-Updates
# Written by Challenger 2 (Empirical Challenger)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_framework.sh"

echo -e "${COLOR_BOLD}Starting Adversarial Challenge Test Suite${COLOR_RESET}"

# ==============================================================================
# PART 1: Compositor Argument Retention & Session Detection Adversarial Tests
# ==============================================================================

test_cli_arg_retention_multiple_compositors() {
    source "$LINKA_SCRIPT"
    preflight
    run_installer_ui() { return 1; }

    SELECTED_COMPOSITORS=()
    flow_install install hyprland niri || true
    assert_eq "${SELECTED_COMPOSITORS[*]}" "hyprland niri" "Multiple compositors ('hyprland niri') must be retained in SELECTED_COMPOSITORS"
}
run_test "test_cli_arg_retention_multiple_compositors" test_cli_arg_retention_multiple_compositors "ADV_COMP"

test_cli_arg_retention_case_insensitive() {
    source "$LINKA_SCRIPT"
    preflight
    run_installer_ui() { return 1; }

    SELECTED_COMPOSITORS=()
    flow_install install HyPrLaNd SWAY || true
    assert_eq "${SELECTED_COMPOSITORS[*]}" "hyprland sway" "Mixed-case arguments ('HyPrLaNd SWAY') must be normalized to 'hyprland sway'"
}
run_test "test_cli_arg_retention_case_insensitive" test_cli_arg_retention_case_insensitive "ADV_COMP"

test_cli_arg_beats_active_running_session() {
    source "$LINKA_SCRIPT"
    preflight
    run_installer_ui() { return 1; }

    # Simulate active Sway session
    export XDG_CURRENT_DESKTOP="sway"
    export DESKTOP_SESSION="sway"
    export SWAYSOCK="/tmp/mock_sway.sock"

    SELECTED_COMPOSITORS=()
    flow_install install niri || true
    assert_eq "${SELECTED_COMPOSITORS[*]}" "niri" "CLI argument 'niri' must override currently running sway session"

    unset SWAYSOCK
    export XDG_CURRENT_DESKTOP=""
    export DESKTOP_SESSION=""
}
run_test "test_cli_arg_beats_active_running_session" test_cli_arg_beats_active_running_session "ADV_COMP"

test_cli_arg_beats_saved_state() {
    source "$LINKA_SCRIPT"
    preflight
    run_installer_ui() { return 1; }

    # Setup saved state with sway
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "SELECTED_COMPOSITORS=sway" > "$STATE_FILE"

    SELECTED_COMPOSITORS=()
    flow_install install hyprland || true
    assert_eq "${SELECTED_COMPOSITORS[*]}" "hyprland" "CLI argument 'hyprland' must take precedence over saved state 'sway'"
}
run_test "test_cli_arg_beats_saved_state" test_cli_arg_beats_saved_state "ADV_COMP"

test_saved_state_beats_running_session() {
    source "$LINKA_SCRIPT"
    preflight

    # Scenario: User previously chose and saved niri.
    # Currently running in a Sway session.
    SELECTED_COMPOSITORS_SAVED=(niri)
    SELECTED_COMPOSITORS=()
    export XDG_CURRENT_DESKTOP="sway"
    export DESKTOP_SESSION="sway"
    export SWAYSOCK="/tmp/mock_sway.sock"

    init_compositor_detection

    assert_eq "${SELECTED_COMPOSITORS[*]}" "niri" "Saved compositor selection 'niri' must not be overridden by running session 'sway'"

    unset SWAYSOCK
    export XDG_CURRENT_DESKTOP=""
    export DESKTOP_SESSION=""
}
run_test "test_saved_state_beats_running_session" test_saved_state_beats_running_session "ADV_COMP"

test_saved_multi_state_beats_running_session() {
    source "$LINKA_SCRIPT"
    preflight

    # Scenario: Saved multi-compositor choice
    SELECTED_COMPOSITORS_SAVED=(hyprland niri)
    SELECTED_COMPOSITORS=()
    export XDG_CURRENT_DESKTOP="sway"
    export DESKTOP_SESSION="sway"

    init_compositor_detection

    assert_eq "${SELECTED_COMPOSITORS[*]}" "hyprland niri" "Saved multi-compositor selection ('hyprland niri') must be preserved over running session"

    export XDG_CURRENT_DESKTOP=""
    export DESKTOP_SESSION=""
}
run_test "test_saved_multi_state_beats_running_session" test_saved_multi_state_beats_running_session "ADV_COMP"

test_cli_arg_retention_reinstall() {
    source "$LINKA_SCRIPT"
    preflight
    run_installer_ui() { return 1; }

    SELECTED_COMPOSITORS=()
    flow_install reinstall sway || true
    assert_eq "${SELECTED_COMPOSITORS[*]}" "sway" "CLI argument 'sway' must be retained during reinstall"
    assert_eq "$IS_REINSTALL" "true" "IS_REINSTALL flag must be set to true"
}
run_test "test_cli_arg_retention_reinstall" test_cli_arg_retention_reinstall "ADV_COMP"

test_non_interactive_without_compositor_fails() {
    source "$LINKA_SCRIPT"
    preflight

    # Emulate non-interactive TTY (stdin is not a tty)
    SELECTED_COMPOSITORS=()
    SELECTED_COMPOSITORS_SAVED=()

    local rc=0
    # In subshell with </dev/null
    (
        run_installer_ui
    ) </dev/null || rc=$?

    assert_eq "$rc" "1" "run_installer_ui without TTY and without selected compositor must return 1"
}
run_test "test_non_interactive_without_compositor_fails" test_non_interactive_without_compositor_fails "ADV_COMP"

test_non_interactive_with_cli_compositor_succeeds() {
    source "$LINKA_SCRIPT"
    preflight

    # Emulate non-interactive TTY with CLI compositor preselected
    SELECTED_COMPOSITORS=(hyprland)

    local rc=0
    (
        run_installer_ui
    ) </dev/null || rc=$?

    assert_eq "$rc" "0" "run_installer_ui without TTY but with selected compositor must succeed (return 0)"
}
run_test "test_non_interactive_with_cli_compositor_succeeds" test_non_interactive_with_cli_compositor_succeeds "ADV_COMP"

test_selected_compositors_string_multi() {
    source "$LINKA_SCRIPT"
    preflight

    SELECTED_COMPOSITORS=(hyprland niri sway)
    assert_eq "$(selected_compositors_string)" "hyprland niri sway" "selected_compositors_string formats correctly"
}
run_test "test_selected_compositors_string_multi" test_selected_compositors_string_multi "ADV_COMP"

# ==============================================================================
# PART 2: SDDM Display Manager Conflict Detection Adversarial Tests
# ==============================================================================

test_sddm_conflict_gdm_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="/usr/lib/systemd/system/gdm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must return 0 for GDM link"
}
run_test "test_sddm_conflict_gdm_link" test_sddm_conflict_gdm_link "ADV_SDDM"

test_sddm_conflict_lightdm_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="/usr/lib/systemd/system/lightdm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must return 0 for LightDM link"
}
run_test "test_sddm_conflict_lightdm_link" test_sddm_conflict_lightdm_link "ADV_SDDM"

test_sddm_conflict_greetd_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="/usr/lib/systemd/system/greetd.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must return 0 for greetd link"
}
run_test "test_sddm_conflict_greetd_link" test_sddm_conflict_greetd_link "ADV_SDDM"

test_sddm_conflict_lxdm_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="/usr/lib/systemd/system/lxdm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must return 0 for LXDM link"
}
run_test "test_sddm_conflict_lxdm_link" test_sddm_conflict_lxdm_link "ADV_SDDM"

test_sddm_conflict_custom_dm_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="/usr/lib/systemd/system/cosmic-greeter.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must return 0 for any non-sddm DM link (e.g. cosmic-greeter)"
}
run_test "test_sddm_conflict_custom_dm_link" test_sddm_conflict_custom_dm_link "ADV_SDDM"

test_sddm_no_conflict_sddm_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="/usr/lib/systemd/system/sddm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_ne "$rc" "0" "other_display_manager_enabled must return non-zero when display-manager link points to sddm.service"
}
run_test "test_sddm_no_conflict_sddm_link" test_sddm_no_conflict_sddm_link "ADV_SDDM"

test_sddm_conflict_gdm_active_no_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="none"
    export MOCK_SYSTEMD_SYSTEM_UNITS="gdm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must detect active/enabled gdm.service without link"
}
run_test "test_sddm_conflict_gdm_active_no_link" test_sddm_conflict_gdm_active_no_link "ADV_SDDM"

test_sddm_conflict_lightdm_active_no_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="none"
    export MOCK_SYSTEMD_SYSTEM_UNITS="lightdm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must detect active/enabled lightdm.service without link"
}
run_test "test_sddm_conflict_lightdm_active_no_link" test_sddm_conflict_lightdm_active_no_link "ADV_SDDM"

test_sddm_conflict_greetd_active_no_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="none"
    export MOCK_SYSTEMD_SYSTEM_UNITS="greetd.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must detect active/enabled greetd.service without link"
}
run_test "test_sddm_conflict_greetd_active_no_link" test_sddm_conflict_greetd_active_no_link "ADV_SDDM"

test_sddm_conflict_lxdm_active_no_link() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="none"
    export MOCK_SYSTEMD_SYSTEM_UNITS="lxdm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must detect active/enabled lxdm.service without link"
}
run_test "test_sddm_conflict_lxdm_active_no_link" test_sddm_conflict_lxdm_active_no_link "ADV_SDDM"

test_sddm_no_conflict_clean_system() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="none"
    export MOCK_SYSTEMD_SYSTEM_UNITS=""

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_ne "$rc" "0" "other_display_manager_enabled must return non-zero on clean system with no DMs"
}
run_test "test_sddm_no_conflict_clean_system" test_sddm_no_conflict_clean_system "ADV_SDDM"

test_sddm_no_conflict_sddm_active() {
    source "$LINKA_SCRIPT"
    preflight
    export MOCK_DM_LINK="none"
    export MOCK_SYSTEMD_SYSTEM_UNITS="sddm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_ne "$rc" "0" "other_display_manager_enabled must return non-zero when only sddm.service is active"
}
run_test "test_sddm_no_conflict_sddm_active" test_sddm_no_conflict_sddm_active "ADV_SDDM"

test_setup_sddm_conflict_behavior() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=true

    local mock_repo="$TEST_TMPDIR/fake_repo"
    mkdir -p "$mock_repo/config/sddm/themes/material-you"
    touch "$mock_repo/config/sddm/themes/material-you/Main.qml"

    export MOCK_RPM_INSTALLED_PKGS="sddm qt6-qtdeclarative qt6-qtsvg"
    export MOCK_DM_LINK="/usr/lib/systemd/system/gdm.service"

    local rc=0
    setup_sddm "$mock_repo" || rc=$?
    assert_eq "$rc" "0" "setup_sddm must return 0 even when DM conflict occurs"

    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    assert_file_not_contains "$enabled_log" "sddm.service" "sddm.service must not be enabled when GDM is active"
}
run_test "test_setup_sddm_conflict_behavior" test_setup_sddm_conflict_behavior "ADV_SDDM"

test_setup_sddm_clean_enables_service() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=true

    SDDM_THEME_DIR="$MOCK_ROOT/usr/share/sddm/themes/material-you"
    SDDM_MANAGED_CONF="$MOCK_ROOT/etc/sddm.conf.d/linka-serpantinum.conf"

    local mock_repo="$TEST_TMPDIR/fake_repo"
    mkdir -p "$mock_repo/config/sddm/themes/material-you"
    touch "$mock_repo/config/sddm/themes/material-you/Main.qml"

    export MOCK_RPM_INSTALLED_PKGS="sddm qt6-qtdeclarative qt6-qtsvg"
    export MOCK_DM_LINK="none"
    export MOCK_SYSTEMD_SYSTEM_UNITS=""

    local rc=0
    setup_sddm "$mock_repo" || rc=$?
    assert_eq "$rc" "0" "setup_sddm must succeed"

    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    assert_file_exists "$enabled_log" "systemctl enabled log must exist"
    assert_file_contains "$enabled_log" "sddm.service" "sddm.service must be enabled"

    assert_file_contains "$STATE_FILE" "SDDM_ENABLED_BY_LINKA=true" "SDDM_ENABLED_BY_LINKA state must be recorded as true"
}
run_test "test_setup_sddm_clean_enables_service" test_setup_sddm_clean_enables_service "ADV_SDDM"

# ==============================================================================
# PART 3: Auto-Update Return Code Handling Adversarial Tests
# ==============================================================================

test_auto_update_exit_0_notify() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=0

    local rc=0
    auto_system_fedora notify || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora notify on rc=0 must return 0"

    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_not_exists "$notify_log" "No notification should be sent when exit code is 0"
    assert_file_contains "$AUTO_CONF" "AUTO_LAST_SYSTEM=" "Timestamp must be updated on rc=0"
}
run_test "test_auto_update_exit_0_notify" test_auto_update_exit_0_notify "ADV_AUTO"

test_auto_update_exit_0_apply() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=0

    local rc=0
    auto_system_fedora apply || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora apply on rc=0 must return 0"

    local upgrade_log="$MOCK_LOGS/dnf_upgrade.log"
    assert_file_not_exists "$upgrade_log" "No upgrade should be performed when exit code is 0"
    assert_file_contains "$AUTO_CONF" "AUTO_LAST_SYSTEM=" "Timestamp must be updated on rc=0"
}
run_test "test_auto_update_exit_0_apply" test_auto_update_exit_0_apply "ADV_AUTO"

test_auto_update_exit_100_notify() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=100

    local rc=0
    auto_system_fedora notify || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora notify on rc=100 must return 0"

    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_exists "$notify_log" "Notification log must exist on rc=100"
    assert_file_contains "$notify_log" "Обновления системы" "Notification title must indicate updates"
    assert_file_contains "$notify_log" "sudo dnf upgrade" "Notification body must include upgrade hint"
    assert_file_contains "$AUTO_CONF" "AUTO_LAST_SYSTEM=" "Timestamp must be updated on notify"
}
run_test "test_auto_update_exit_100_notify" test_auto_update_exit_100_notify "ADV_AUTO"

test_auto_update_exit_100_apply_success() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=100
    export MOCK_NEEDS_RESTARTING=0

    local rc=0
    auto_system_fedora apply || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora apply on rc=100 must return 0"

    local upgrade_log="$MOCK_LOGS/dnf_upgrade.log"
    assert_file_exists "$upgrade_log" "Upgrade log must exist"
    assert_file_contains "$upgrade_log" "UPGRADE:" "Upgrade command was executed"

    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_exists "$notify_log" "Notification log must exist"
    assert_file_contains "$notify_log" "Система обновлена" "Success notification must be sent"
    assert_file_contains "$AUTO_CONF" "AUTO_LAST_SYSTEM=" "Timestamp must be updated"
}
run_test "test_auto_update_exit_100_apply_success" test_auto_update_exit_100_apply_success "ADV_AUTO"

test_auto_update_exit_100_apply_reboot_required() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=100
    export MOCK_NEEDS_RESTARTING=1

    local rc=0
    auto_system_fedora apply || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora apply must return 0"

    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_exists "$notify_log" "Notification log must exist"
    assert_file_contains "$notify_log" "перезагрузка" "Notification must contain reboot notice"
}
run_test "test_auto_update_exit_100_apply_reboot_required" test_auto_update_exit_100_apply_reboot_required "ADV_AUTO"

test_auto_update_exit_100_apply_sudo_password_prompts() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=100
    export MOCK_SUDO_FAIL=1

    local rc=0
    auto_system_fedora apply || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora must gracefully return 0 when sudo requires password"

    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_exists "$notify_log" "Notification log must exist"
    assert_file_contains "$notify_log" "sudo просит пароль" "Notification must alert user about sudo password requirement"

    local upgrade_log="$MOCK_LOGS/dnf_upgrade.log"
    assert_file_not_exists "$upgrade_log" "Upgrade must not be attempted if sudo validation fails"
}
run_test "test_auto_update_exit_100_apply_sudo_password_prompts" test_auto_update_exit_100_apply_sudo_password_prompts "ADV_AUTO"

test_auto_update_exit_100_apply_upgrade_failure() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=100
    export MOCK_DNF_UPGRADE_EXIT_CODE=1

    local rc=0
    auto_system_fedora apply || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora must handle upgrade failure gracefully without crashing"

    local notify_log="$MOCK_LOGS/notify.log"
    assert_file_exists "$notify_log" "Notification log must exist"
    assert_file_contains "$notify_log" "Обновление системы не удалось" "Notification must alert user about failure"
}
run_test "test_auto_update_exit_100_apply_upgrade_failure" test_auto_update_exit_100_apply_upgrade_failure "ADV_AUTO"

test_auto_update_various_error_exit_codes() {
    source "$LINKA_SCRIPT"
    preflight

    for err_code in 1 2 3 127 255; do
        export MOCK_DNF_CHECK_UPDATE_EXIT_CODE="$err_code"
        local rc=0
        auto_system_fedora notify || rc=$?
        assert_eq "$rc" "0" "auto_system_fedora notify on error exit code $err_code must return 0"

        local upgrade_log="$MOCK_LOGS/dnf_upgrade.log"
        assert_file_not_exists "$upgrade_log" "Upgrade must not be run on exit code $err_code"
    done
}
run_test "test_auto_update_various_error_exit_codes" test_auto_update_various_error_exit_codes "ADV_AUTO"

test_auto_update_missing_dnf_binary() {
    source "$LINKA_SCRIPT"
    preflight

    # Strip dnf and dnf5 from PATH
    local original_path="$PATH"
    local clean_path
    clean_path="$(echo "$PATH" | tr ':' '\n' | grep -v "$MOCK_BIN_DIR" | tr '\n' ':')"
    export PATH="$clean_path"

    # Also shadow command -v
    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "dnf" || "${2:-}" == "dnf5" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }

    local rc=0
    auto_system_fedora notify || rc=$?
    assert_eq "$rc" "0" "auto_system_fedora must return 0 when dnf binary is not found"

    export PATH="$original_path"
}
run_test "test_auto_update_missing_dnf_binary" test_auto_update_missing_dnf_binary "ADV_AUTO"

# ==============================================================================
# Suite Summary
# ==============================================================================
print_suite_summary "Adversarial Challenge Tests"
