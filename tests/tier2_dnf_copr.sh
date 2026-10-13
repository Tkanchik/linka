#!/usr/bin/env bash
# ==============================================================================
# Tier 2 Test Suite: DNF4/DNF5 Compatibility & COPR Management (F3, F4, F5)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_framework.sh"

echo -e "${COLOR_BOLD}Starting Tier 2 Test Suite: DNF4/DNF5 & COPR Compatibility${COLOR_RESET}"

# ------------------------------------------------------------------------------
# Test 2.1 (F3): fedora_ensure_copr_plugin in DNF4 environment
# ------------------------------------------------------------------------------
test_copr_plugin_dnf4_installs_plugins_core() {
    export MOCK_DNF_VERSION="4"
    export MOCK_COPR_PLUGIN_ENABLED="0"
    rm -f "$MOCK_DNF_STATE/copr_plugin_active"

    source "$LINKA_SCRIPT"
    preflight

    local rc=0
    fedora_ensure_copr_plugin || rc=$?
    assert_eq "$rc" "0" "fedora_ensure_copr_plugin should return 0 in DNF4 environment"

    # Verify dnf install log contains dnf-plugins-core
    local install_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$install_log" "dnf install log must exist"
    assert_file_contains "$install_log" "dnf-plugins-core" "DNF4 environment must install dnf-plugins-core"
}
run_test "test_copr_plugin_dnf4_installs_plugins_core" test_copr_plugin_dnf4_installs_plugins_core "F3"

# ------------------------------------------------------------------------------
# Test 2.2 (F3): fedora_ensure_copr_plugin in DNF5 environment
# ------------------------------------------------------------------------------
test_copr_plugin_dnf5_installs_dnf5_plugins() {
    export MOCK_DNF_VERSION="5"
    export MOCK_COPR_PLUGIN_ENABLED="0"
    rm -f "$MOCK_DNF_STATE/copr_plugin_active"

    source "$LINKA_SCRIPT"
    preflight

    local rc=0
    fedora_ensure_copr_plugin || rc=$?
    assert_eq "$rc" "0" "fedora_ensure_copr_plugin should return 0 in DNF5 environment"

    # Verify dnf install log contains dnf5-plugins
    local install_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$install_log" "dnf install log must exist"
    assert_file_contains "$install_log" "dnf5-plugins" "DNF5 environment must install dnf5-plugins"
}
run_test "test_copr_plugin_dnf5_installs_dnf5_plugins" test_copr_plugin_dnf5_installs_dnf5_plugins "F3"

# ------------------------------------------------------------------------------
# Test 2.3 (F3): fedora_ensure_copr_plugin early return when copr works
# ------------------------------------------------------------------------------
test_copr_plugin_already_present_skips_install() {
    export MOCK_DNF_VERSION="5"
    export MOCK_COPR_PLUGIN_ENABLED="1"
    echo "1" > "$MOCK_DNF_STATE/copr_plugin_active"

    source "$LINKA_SCRIPT"
    preflight

    local rc=0
    fedora_ensure_copr_plugin || rc=$?
    assert_eq "$rc" "0" "fedora_ensure_copr_plugin should return 0 immediately"

    # No packages should be installed
    local install_log="$MOCK_LOGS/dnf_install.log"
    assert_file_not_exists "$install_log" "No packages should be installed when copr plugin is already working"
}
run_test "test_copr_plugin_already_present_skips_install" test_copr_plugin_already_present_skips_install "F3"

# ------------------------------------------------------------------------------
# Test 2.4 (F4): fedora_enable_copr executes non-interactively with -y
# ------------------------------------------------------------------------------
test_copr_enable_non_interactive_has_dash_y() {
    export MOCK_COPR_PLUGIN_ENABLED="1"
    echo "1" > "$MOCK_DNF_STATE/copr_plugin_active"

    source "$LINKA_SCRIPT"
    preflight

    local rc=0
    fedora_enable_copr "solopasha/hyprland" || rc=$?
    assert_eq "$rc" "0" "fedora_enable_copr should succeed"

    # Check mock copr log
    local copr_log="$MOCK_LOGS/dnf_copr.log"
    assert_file_exists "$copr_log" "COPR log must exist"
    assert_file_contains "$copr_log" "REPO=solopasha/hyprland HAS_Y=1" "COPR enable must be non-interactive with -y"
}
run_test "test_copr_enable_non_interactive_has_dash_y" test_copr_enable_non_interactive_has_dash_y "F4"

# ------------------------------------------------------------------------------
# Test 2.5 (F4): Non-interactive quickshell COPR enable during install_dependencies
# ------------------------------------------------------------------------------
test_quickshell_copr_enable_on_install() {
    export MOCK_COPR_PLUGIN_ENABLED="1"
    echo "1" > "$MOCK_DNF_STATE/copr_plugin_active"

    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=false
    install_dependencies

    local copr_log="$MOCK_LOGS/dnf_copr.log"
    assert_file_exists "$copr_log" "COPR log must exist"
    assert_file_contains "$copr_log" "errornointernet/quickshell" "quickshell COPR repo must be enabled during install_dependencies"
    assert_file_contains "$copr_log" "HAS_Y=1" "quickshell COPR enable must include -y"
}
run_test "test_quickshell_copr_enable_on_install" test_quickshell_copr_enable_on_install "F4"

# ------------------------------------------------------------------------------
# Test 2.6 (F5): Pre-enable solopasha/hyprland COPR before OPTIONAL_PKGS loop
# ------------------------------------------------------------------------------
test_copr_solopasha_hyprland_pre_enabled_for_optional_pkgs() {
    export MOCK_COPR_PLUGIN_ENABLED="1"
    echo "1" > "$MOCK_DNF_STATE/copr_plugin_active"

    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=false

    # Call install_dependencies with Niri (Hyprland NOT requested)
    # Even when Hyprland is not selected, solopasha/hyprland must be pre-enabled
    # so matugen and satty in OPTIONAL_PKGS can be found and installed.
    install_dependencies "niri"

    local copr_log="$MOCK_LOGS/dnf_copr.log"
    assert_file_exists "$copr_log" "COPR log must exist"
    assert_file_contains "$copr_log" "solopasha/hyprland" "solopasha/hyprland COPR must be pre-enabled for OPTIONAL_PKGS (matugen, satty)"
}
run_test "test_copr_solopasha_hyprland_pre_enabled_for_optional_pkgs" test_copr_solopasha_hyprland_pre_enabled_for_optional_pkgs "F5"

# ------------------------------------------------------------------------------
# Test 2.7 (F5): Isolated installation of OPTIONAL_PKGS with --skip-unavailable
# ------------------------------------------------------------------------------
test_optional_pkgs_isolated_installation_with_skip_unavailable() {
    export MOCK_COPR_PLUGIN_ENABLED="1"
    echo "1" > "$MOCK_DNF_STATE/copr_plugin_active"

    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=false

    # Simulate that matugen and satty fail to install (or are missing), but others succeed
    install_dependencies

    # Check that dnf invocations include --skip-unavailable for optional pkgs
    local dnf_log="$MOCK_LOGS/dnf.log"
    assert_file_exists "$dnf_log" "dnf log must exist"
    assert_file_contains "$dnf_log" "install -y --skip-unavailable" "Optional packages must be installed with --skip-unavailable"
}
run_test "test_optional_pkgs_isolated_installation_with_skip_unavailable" test_optional_pkgs_isolated_installation_with_skip_unavailable "F5"

# ------------------------------------------------------------------------------
# Test 2.8 (F5): Already installed optional packages are skipped
# ------------------------------------------------------------------------------
test_optional_pkgs_already_installed_skipped() {
    export MOCK_COPR_PLUGIN_ENABLED="1"
    echo "1" > "$MOCK_DNF_STATE/copr_plugin_active"
    export MOCK_RPM_INSTALLED_PKGS="quickshell matugen satty cliphist wl-gammarelay-rs"

    source "$LINKA_SCRIPT"
    preflight
    OPT_SDDM=false

    install_dependencies

    # In dnf_install.log, there should be no standalone optional package install line
    local install_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$install_log" "dnf install log must exist"
    # The primary transaction contains REQUIRED_PKGS, but separate optional package install calls should be skipped
    local dnf_calls
    dnf_calls=$(grep -E '^(quickshell|matugen|satty|cliphist|wl-gammarelay-rs)$' "$install_log" || true)
    assert_eq "$dnf_calls" "" "Already installed optional packages must not be re-requested individually"
}
run_test "test_optional_pkgs_already_installed_skipped" test_optional_pkgs_already_installed_skipped "F5"

print_suite_summary "Tier 2: DNF4/DNF5 & COPR Compatibility"
