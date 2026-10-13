#!/usr/bin/env bash
# ==============================================================================
# Tier 1 Test Suite: Sanity, Package Lists & System Auditing (F1, F2, F12)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_framework.sh"

echo -e "${COLOR_BOLD}Starting Tier 1 Test Suite: Sanity & Package Lists Audit${COLOR_RESET}"

# ------------------------------------------------------------------------------
# Test 1.1 (F12): Syntax Integrity of Bash Scripts
# ------------------------------------------------------------------------------
test_syntax_integrity_linka() {
    local rc=0
    bash -n "$LINKA_SCRIPT" >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "0" "bash -n linka must return exit code 0"

    rc=0
    bash -n "$REPO_ROOT/install.sh" >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "0" "bash -n install.sh must return exit code 0"
}
run_test "test_syntax_integrity_linka" test_syntax_integrity_linka "F12"

# ------------------------------------------------------------------------------
# Test 1.2 (F1): Fedora REQUIRED_PKGS must exclude cliphist
# ------------------------------------------------------------------------------
test_fedora_required_pkgs_cliphist_excluded() {
    source "$LINKA_SCRIPT"
    preflight

    local pkg
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if [[ "$pkg" == "cliphist" ]]; then
            echo "Error: cliphist found in REQUIRED_PKGS on Fedora" >&2
            return 1
        fi
    done
    return 0
}
run_test "test_fedora_required_pkgs_cliphist_excluded" test_fedora_required_pkgs_cliphist_excluded "F1"

# ------------------------------------------------------------------------------
# Test 1.3 (F1): Fedora OPTIONAL_PKGS must include cliphist
# ------------------------------------------------------------------------------
test_fedora_optional_pkgs_cliphist_included() {
    source "$LINKA_SCRIPT"
    preflight

    local found=0 pkg
    for pkg in "${OPTIONAL_PKGS[@]}"; do
        if [[ "$pkg" == "cliphist" ]]; then
            found=1
            break
        fi
    done

    assert_eq "$found" "1" "cliphist must be placed in OPTIONAL_PKGS for Fedora"
}
run_test "test_fedora_optional_pkgs_cliphist_included" test_fedora_optional_pkgs_cliphist_included "F1"

# ------------------------------------------------------------------------------
# Test 1.4 (F1): SDDM_PKGS and BOOTSTRAP_PKGS Validation
# ------------------------------------------------------------------------------
test_fedora_sddm_and_bootstrap_pkgs() {
    source "$LINKA_SCRIPT"
    preflight

    # Check SDDM_PKGS
    local sddm_str="${SDDM_PKGS[*]}"
    assert_match "sddm" "$sddm_str" "SDDM_PKGS must contain sddm"
    assert_match "qt6-qtdeclarative" "$sddm_str" "SDDM_PKGS must contain qt6-qtdeclarative"
    assert_match "qt6-qtsvg" "$sddm_str" "SDDM_PKGS must contain qt6-qtsvg"

    # Check BOOTSTRAP_PKGS
    local boot_str="${BOOTSTRAP_PKGS[*]}"
    assert_match "jq" "$boot_str" "BOOTSTRAP_PKGS must contain jq"
    assert_match "curl" "$boot_str" "BOOTSTRAP_PKGS must contain curl"
    assert_match "git" "$boot_str" "BOOTSTRAP_PKGS must contain git"
    assert_match "unzip" "$boot_str" "BOOTSTRAP_PKGS must contain unzip"
    assert_match "fontconfig" "$boot_str" "BOOTSTRAP_PKGS must contain fontconfig"
}
run_test "test_fedora_sddm_and_bootstrap_pkgs" test_fedora_sddm_and_bootstrap_pkgs "F1"

# ------------------------------------------------------------------------------
# Test 1.5 (F1): pkg_installed virtual provides resolution (wget2-wget -> wget)
# ------------------------------------------------------------------------------
test_pkg_installed_virtual_provides() {
    source "$LINKA_SCRIPT"
    preflight

    # Case A: rpm -q fails, but rpm -q --whatprovides succeeds
    export MOCK_RPM_INSTALLED_PKGS="wget2-wget"
    export MOCK_RPM_PROVIDES="wget:wget2-wget"

    local rc=0
    pkg_installed "wget" || rc=$?
    assert_eq "$rc" "0" "pkg_installed should succeed for virtual provide (wget provided by wget2-wget)"

    # Case B: package absent from rpm entirely, but binary exists on PATH
    local mock_bin_tool="$MOCK_BIN_DIR/mockcustomtool"
    touch "$mock_bin_tool" && chmod +x "$mock_bin_tool"
    rc=0
    pkg_installed "mockcustomtool" || rc=$?
    rm -f "$mock_bin_tool"
    assert_eq "$rc" "0" "pkg_installed should return 0 when binary is on PATH"

    # Case C: package completely absent
    rc=0
    pkg_installed "nonexistent-pkg-xyz" || rc=$?
    assert_ne "$rc" "0" "pkg_installed must return non-zero for nonexistent package"
}
run_test "test_pkg_installed_virtual_provides" test_pkg_installed_virtual_provides "F1"

# ------------------------------------------------------------------------------
# Test 1.6 (F2): Multimedia conflict: ffmpeg-free skipped when ffmpeg installed
# ------------------------------------------------------------------------------
test_multimedia_conflict_ffmpeg_installed() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_RPM_INSTALLED_PKGS="ffmpeg"
    OPT_SDDM=false
    install_dependencies

    # Verify dnf install log does not include ffmpeg-free
    local dnf_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$dnf_log" "dnf install log must exist"
    assert_file_not_contains "$dnf_log" "ffmpeg-free" "ffmpeg-free must be skipped when ffmpeg is installed"
}
run_test "test_multimedia_conflict_ffmpeg_installed" test_multimedia_conflict_ffmpeg_installed "F2"

# ------------------------------------------------------------------------------
# Test 1.7 (F2): Multimedia conflict: ffmpeg-free skipped when ffmpeg-libs installed
# ------------------------------------------------------------------------------
test_multimedia_conflict_ffmpeg_libs_installed() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_RPM_INSTALLED_PKGS="ffmpeg-libs"
    OPT_SDDM=false
    install_dependencies

    local dnf_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$dnf_log" "dnf install log must exist"
    assert_file_not_contains "$dnf_log" "ffmpeg-free" "ffmpeg-free must be skipped when ffmpeg-libs is installed"
}
run_test "test_multimedia_conflict_ffmpeg_libs_installed" test_multimedia_conflict_ffmpeg_libs_installed "F2"

# ------------------------------------------------------------------------------
# Test 1.8 (F2): Multimedia conflict: ffmpeg-free included on clean system
# ------------------------------------------------------------------------------
test_multimedia_clean_system_ffmpeg_free_included() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_RPM_INSTALLED_PKGS=""
    OPT_SDDM=false
    install_dependencies

    local dnf_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$dnf_log" "dnf install log must exist"
    assert_file_contains "$dnf_log" "ffmpeg-free" "ffmpeg-free must be included on clean system"
}
run_test "test_multimedia_clean_system_ffmpeg_free_included" test_multimedia_clean_system_ffmpeg_free_included "F2"

# ------------------------------------------------------------------------------
# Test 1.9 (F2): Power daemon conflict: power-profiles-daemon skipped when tuned-ppd installed
# ------------------------------------------------------------------------------
test_power_daemon_conflict_tuned_ppd_installed() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_RPM_INSTALLED_PKGS="tuned-ppd"
    OPT_SDDM=false
    install_dependencies

    local dnf_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$dnf_log" "dnf install log must exist"
    assert_file_not_contains "$dnf_log" "power-profiles-daemon" "power-profiles-daemon must be skipped when tuned-ppd is installed"
}
run_test "test_power_daemon_conflict_tuned_ppd_installed" test_power_daemon_conflict_tuned_ppd_installed "F2"

# ------------------------------------------------------------------------------
# Test 1.10 (F2): Power daemon: power-profiles-daemon included when tuned-ppd absent
# ------------------------------------------------------------------------------
test_power_daemon_clean_system_ppd_included() {
    source "$LINKA_SCRIPT"
    preflight

    export MOCK_RPM_INSTALLED_PKGS=""
    OPT_SDDM=false
    install_dependencies

    local dnf_log="$MOCK_LOGS/dnf_install.log"
    assert_file_exists "$dnf_log" "dnf install log must exist"
    assert_file_contains "$dnf_log" "power-profiles-daemon" "power-profiles-daemon must be included when tuned-ppd is absent"
}
run_test "test_power_daemon_clean_system_ppd_included" test_power_daemon_clean_system_ppd_included "F2"

# ------------------------------------------------------------------------------
# Test 1.11 (F2): Binary handling: fdfind to fd symlink creation
# ------------------------------------------------------------------------------
test_binary_handling_fdfind_symlink() {
    # Create fake fdfind in a mock directory
    local mock_fdfind_dir="$TEST_TMPDIR/fake_bin"
    mkdir -p "$mock_fdfind_dir"
    touch "$mock_fdfind_dir/fdfind" && chmod +x "$mock_fdfind_dir/fdfind"

    # Run in subshell where fd is not found but fdfind is found
    (
        export PATH="$mock_fdfind_dir:$PATH"
        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "fd" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        source "$LINKA_SCRIPT"
        preflight
        OPT_SDDM=false
        install_dependencies
    )

    # Verify symlink was created via sudo ln
    local sudo_log="$MOCK_LOGS/sudo.log"
    assert_file_exists "$sudo_log" "sudo log must exist"
    assert_file_contains "$sudo_log" "ln -sfn .*fdfind .*fd" "symlink fdfind -> fd must be created"
}
run_test "test_binary_handling_fdfind_symlink" test_binary_handling_fdfind_symlink "F2"

print_suite_summary "Tier 1: Sanity & Package Lists Audit"
