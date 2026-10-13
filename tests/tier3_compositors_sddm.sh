#!/usr/bin/env bash
# ==============================================================================
# Tier 3 Test Suite: Compositors & SDDM Display Manager Integration (F6, F7, F8, F9)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_framework.sh"

echo -e "${COLOR_BOLD}Starting Tier 3 Test Suite: Compositors & SDDM Integration${COLOR_RESET}"

# ------------------------------------------------------------------------------
# Test 3.1 (F6): CLI argument retention: linka install <comp>
# ------------------------------------------------------------------------------
test_cli_argument_retention_install_compositors() {
    source "$LINKA_SCRIPT"
    preflight

    # Stub UI to return immediately
    run_installer_ui() { return 1; }

    # Test Hyprland CLI argument
    SELECTED_COMPOSITORS=()
    flow_install install hyprland || true
    assert_eq "${SELECTED_COMPOSITORS[*]}" "hyprland" "CLI argument 'hyprland' must be retained in SELECTED_COMPOSITORS"

    # Test Niri CLI argument
    SELECTED_COMPOSITORS=()
    flow_install install niri || true
    assert_eq "${SELECTED_COMPOSITORS[*]}" "niri" "CLI argument 'niri' must be retained in SELECTED_COMPOSITORS"

    # Test Sway CLI argument
    SELECTED_COMPOSITORS=()
    flow_install install sway || true
    assert_eq "${SELECTED_COMPOSITORS[*]}" "sway" "CLI argument 'sway' must be retained in SELECTED_COMPOSITORS"
}
run_test "test_cli_argument_retention_install_compositors" test_cli_argument_retention_install_compositors "F6"

# ------------------------------------------------------------------------------
# Test 3.2 (F6): SELECTED_COMPOSITORS_SAVED preserved over running session
# ------------------------------------------------------------------------------
test_compositor_saved_selection_preserved_over_running() {
    source "$LINKA_SCRIPT"
    preflight

    # Scenario: User previously chose and saved Niri.
    # Currently running in a Sway session.
    SELECTED_COMPOSITORS_SAVED=(niri)
    SELECTED_COMPOSITORS=()
    export XDG_CURRENT_DESKTOP="sway"
    export DESKTOP_SESSION="sway"

    init_compositor_detection

    assert_eq "${SELECTED_COMPOSITORS[*]}" "niri" "Saved compositor choice (niri) must not be clobbered by running session (sway)"
}
run_test "test_compositor_saved_selection_preserved_over_running" test_compositor_saved_selection_preserved_over_running "F6"

# ------------------------------------------------------------------------------
# Test 3.3 (F7): comp_atom package mapping
# ------------------------------------------------------------------------------
test_comp_atom_mapping() {
    source "$LINKA_SCRIPT"
    preflight

    assert_eq "$(comp_atom hyprland)" "hyprland" "comp_atom hyprland -> hyprland"
    assert_eq "$(comp_atom niri)" "niri" "comp_atom niri -> niri"
    assert_eq "$(comp_atom sway)" "sway" "comp_atom sway -> sway"
    assert_eq "$(comp_atom HYPRLAND)" "hyprland" "comp_atom HYPRLAND -> hyprland (case insensitive)"
    assert_eq "$(comp_atom Niri)" "niri" "comp_atom Niri -> niri (case insensitive)"
}
run_test "test_comp_atom_mapping" test_comp_atom_mapping "F7"

# ------------------------------------------------------------------------------
# Test 3.4 (F7): is_compositor_installed binary and package detection
# ------------------------------------------------------------------------------
test_is_compositor_installed_detection() {
    source "$LINKA_SCRIPT"
    preflight

    # Case A: Missing entirely
    export MOCK_RPM_INSTALLED_PKGS=""
    local rc=0
    is_compositor_installed hyprland || rc=$?
    assert_ne "$rc" "0" "is_compositor_installed must return non-zero when compositor is missing"

    # Case B: Installed via RPM
    export MOCK_RPM_INSTALLED_PKGS="hyprland"
    rc=0
    is_compositor_installed hyprland || rc=$?
    assert_eq "$rc" "0" "is_compositor_installed must return 0 when compositor package is installed via RPM"

    # Case C: Binary on PATH
    export MOCK_RPM_INSTALLED_PKGS=""
    local mock_niri_bin="$MOCK_BIN_DIR/niri"
    touch "$mock_niri_bin" && chmod +x "$mock_niri_bin"
    rc=0
    is_compositor_installed niri || rc=$?
    rm -f "$mock_niri_bin"
    assert_eq "$rc" "0" "is_compositor_installed must return 0 when binary exists on PATH"
}
run_test "test_is_compositor_installed_detection" test_is_compositor_installed_detection "F7"

# ------------------------------------------------------------------------------
# Test 3.5 (F7): Auto-install missing Hyprland (COPR solopasha/hyprland + dnf install)
# ------------------------------------------------------------------------------
test_auto_install_missing_hyprland() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=false
    export MOCK_RPM_INSTALLED_PKGS=""

    install_dependencies "hyprland"

    local copr_log="$MOCK_LOGS/dnf_copr.log"
    local install_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$copr_log" "COPR log must exist"
    assert_file_contains "$copr_log" "solopasha/hyprland" "solopasha/hyprland COPR must be enabled"
    assert_file_exists "$install_log" "install log must exist"
    assert_file_contains "$install_log" "hyprland" "hyprland package must be installed"
}
run_test "test_auto_install_missing_hyprland" test_auto_install_missing_hyprland "F7"

# ------------------------------------------------------------------------------
# Test 3.6 (F7): Auto-install Niri when available in base repo (no COPR needed)
# ------------------------------------------------------------------------------
test_auto_install_niri_base_repo() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=false
    export MOCK_RPM_INSTALLED_PKGS=""
    export MOCK_DNF_AVAILABLE_PKGS="niri"

    # Mask host niri binary so is_compositor_installed evaluates to false
    command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "niri" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    install_dependencies "niri"

    local install_log="$MOCK_LOGS/dnf_install.log"
    local copr_log="$MOCK_LOGS/dnf_copr.log"
    assert_file_exists "$install_log" "install log must exist"
    assert_file_contains "$install_log" "niri" "niri package must be installed"
    # yalter/niri should not be enabled since niri was found in base repo
    assert_file_not_contains "$copr_log" "yalter/niri" "yalter/niri COPR should not be enabled when niri is in base repo"
}
run_test "test_auto_install_niri_base_repo" test_auto_install_niri_base_repo "F7"

# ------------------------------------------------------------------------------
# Test 3.7 (F7): Auto-install Niri fallback to COPR when absent from base repo
# ------------------------------------------------------------------------------
test_auto_install_niri_copr_fallback() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=false
    export MOCK_RPM_INSTALLED_PKGS=""
    export MOCK_DNF_AVAILABLE_PKGS="" # Niri absent from base repo

    # Mask host niri binary so is_compositor_installed evaluates to false
    command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "niri" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    install_dependencies "niri"

    local copr_log="$MOCK_LOGS/dnf_copr.log"
    local install_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$copr_log" "COPR log must exist"
    assert_file_contains "$copr_log" "yalter/niri" "yalter/niri COPR must be enabled when absent from base repo"
    assert_file_contains "$install_log" "niri" "niri package must be installed"
}
run_test "test_auto_install_niri_copr_fallback" test_auto_install_niri_copr_fallback "F7"

# ------------------------------------------------------------------------------
# Test 3.8 (F7): Auto-install missing Sway
# ------------------------------------------------------------------------------
test_auto_install_missing_sway() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=false
    export MOCK_RPM_INSTALLED_PKGS=""

    install_dependencies "sway"

    local install_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$install_log" "install log must exist"
    assert_file_contains "$install_log" "sway" "sway package must be installed"
}
run_test "test_auto_install_missing_sway" test_auto_install_missing_sway "F7"

# ------------------------------------------------------------------------------
# Test 3.9 (F8): ensure_sddm_package installs missing Qt6 dependencies
# ------------------------------------------------------------------------------
test_ensure_sddm_package_installs_missing_qt6() {
    source "$LINKA_SCRIPT"
    preflight

    # sddm is installed, but qt6-qtdeclarative and qt6-qtsvg are missing
    export MOCK_RPM_INSTALLED_PKGS="sddm"

    local rc=0
    ensure_sddm_package || rc=$?
    assert_eq "$rc" "0" "ensure_sddm_package should succeed"

    local install_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$install_log" "install log must exist"
    assert_file_contains "$install_log" "qt6-qtdeclarative" "missing qt6-qtdeclarative must be installed"
    assert_file_contains "$install_log" "qt6-qtsvg" "missing qt6-qtsvg must be installed"
}
run_test "test_ensure_sddm_package_installs_missing_qt6" test_ensure_sddm_package_installs_missing_qt6 "F8"

# ------------------------------------------------------------------------------
# Test 3.10 (F8): other_display_manager_enabled detects GDM conflict
# ------------------------------------------------------------------------------
test_other_display_manager_conflict_gdm() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DM_LINK="/usr/lib/systemd/system/gdm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_eq "$rc" "0" "other_display_manager_enabled must return 0 when GDM is active/enabled"
}
run_test "test_other_display_manager_conflict_gdm" test_other_display_manager_conflict_gdm "F8"

# ------------------------------------------------------------------------------
# Test 3.11 (F8): other_display_manager_enabled returns 1 for SDDM
# ------------------------------------------------------------------------------
test_other_display_manager_sddm_no_conflict() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_DM_LINK="/usr/lib/systemd/system/sddm.service"

    local rc=0
    other_display_manager_enabled || rc=$?
    assert_ne "$rc" "0" "other_display_manager_enabled must return non-zero when SDDM is already the display manager"
}
run_test "test_other_display_manager_sddm_no_conflict" test_other_display_manager_sddm_no_conflict "F8"

# ------------------------------------------------------------------------------
# Test 3.12 (F8): setup_sddm skips enabling sddm.service when other DM active
# ------------------------------------------------------------------------------
test_setup_sddm_skips_service_on_dm_conflict() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=true

    # Prepare mock theme directory
    local mock_repo="$TEST_TMPDIR/fake_repo"
    mkdir -p "$mock_repo/config/sddm/themes/material-you"
    touch "$mock_repo/config/sddm/themes/material-you/Main.qml"

    export MOCK_RPM_INSTALLED_PKGS="sddm qt6-qtdeclarative qt6-qtsvg"
    export MOCK_DM_LINK="/usr/lib/systemd/system/gdm.service"

    setup_sddm "$mock_repo"

    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    assert_file_not_contains "$enabled_log" "sddm.service" "sddm.service must NOT be enabled when another DM is active"
}
run_test "test_setup_sddm_skips_service_on_dm_conflict" test_setup_sddm_skips_service_on_dm_conflict "F8"

# ------------------------------------------------------------------------------
# Test 3.13 (F8, F9): setup_sddm deploys theme and enables sddm.service cleanly
# ------------------------------------------------------------------------------
test_setup_sddm_deploys_theme_and_config() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=true

    SDDM_THEME_DIR="$MOCK_ROOT/usr/share/sddm/themes/material-you"
    SDDM_MANAGED_CONF="$MOCK_ROOT/etc/sddm.conf.d/linka-serpantinum.conf"

    local mock_repo="$TEST_TMPDIR/fake_repo"
    mkdir -p "$mock_repo/config/sddm/themes/material-you"
    echo "import QtQuick" > "$mock_repo/config/sddm/themes/material-you/Main.qml"

    export MOCK_RPM_INSTALLED_PKGS="sddm qt6-qtdeclarative qt6-qtsvg"
    export MOCK_DM_LINK="" # No conflicting display manager

    setup_sddm "$mock_repo"

    # Verify theme files deployed in MOCK_ROOT
    local theme_dir="$MOCK_ROOT/usr/share/sddm/themes/material-you"
    assert_file_exists "$theme_dir/Main.qml" "Theme Main.qml must be deployed"
    assert_file_exists "$theme_dir/.linka-managed" ".linka-managed marker must exist"

    # Verify sddm drop-in config written
    local sddm_conf="$MOCK_ROOT/etc/sddm.conf.d/linka-serpantinum.conf"
    assert_file_exists "$sddm_conf" "sddm drop-in config must exist"
    assert_file_contains "$sddm_conf" "Current=material-you" "Config must specify material-you theme"

    # Verify sddm.service enabled
    local enabled_log="$MOCK_LOGS/systemctl_enabled.log"
    assert_file_exists "$enabled_log" "systemctl enabled log must exist"
    assert_file_contains "$enabled_log" "sddm.service" "sddm.service must be enabled"
}
run_test "test_setup_sddm_deploys_theme_and_config" test_setup_sddm_deploys_theme_and_config "F9"

# ------------------------------------------------------------------------------
# Test 3.14 (F9): setup_sddm skips unmanaged theme directory
# ------------------------------------------------------------------------------
test_setup_sddm_unmanaged_theme_skipped() {
    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=true

    SDDM_THEME_DIR="$MOCK_ROOT/usr/share/sddm/themes/material-you"
    SDDM_MANAGED_CONF="$MOCK_ROOT/etc/sddm.conf.d/linka-serpantinum.conf"

    local mock_repo="$TEST_TMPDIR/fake_repo"
    mkdir -p "$mock_repo/config/sddm/themes/material-you"
    echo "NEW CONTENT" > "$mock_repo/config/sddm/themes/material-you/Main.qml"

    # Create unmanaged theme dir in mock root
    local unmanaged_theme="$MOCK_ROOT/usr/share/sddm/themes/material-you"
    mkdir -p "$unmanaged_theme"
    echo "USER CUSTOM THEME" > "$unmanaged_theme/Main.qml"
    # Note: no .linka-managed marker and no managed conf!

    export MOCK_RPM_INSTALLED_PKGS="sddm qt6-qtdeclarative qt6-qtsvg"

    setup_sddm "$mock_repo"

    # Verify user custom theme content was NOT overwritten
    assert_file_contains "$unmanaged_theme/Main.qml" "USER CUSTOM THEME" "Unmanaged theme must not be overwritten"
}
run_test "test_setup_sddm_unmanaged_theme_skipped" test_setup_sddm_unmanaged_theme_skipped "F9"

print_suite_summary "Tier 3: Compositors & SDDM Integration"
