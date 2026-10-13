#!/usr/bin/env bash
# ==============================================================================
# Master E2E Test Runner for linka (Fedora Installer & Compatibility Audit)
# Executes test suites across Tiers 1-4 covering Features F1-F12.
# Returns exit code 0 when all executed tests pass.
# ==============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"

# Colors
if [[ -t 1 ]] || [[ "${FORCE_COLOR:-0}" == "1" ]]; then
    COLOR_RESET="\033[0m"
    COLOR_RED="\033[31m"
    COLOR_GREEN="\033[32m"
    COLOR_YELLOW="\033[33m"
    COLOR_BLUE="\033[34m"
    COLOR_CYAN="\033[36m"
    COLOR_BOLD="\033[1m"
else
    COLOR_RESET=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_CYAN=""
    COLOR_BOLD=""
fi

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --tier <1-4>       Run only tests in the specified Tier
  --all              Run all test suites across Tiers 1-4 (default)
  -v, --verbose      Enable verbose output
  -h, --help         Display this help message

Test Tiers:
  Tier 1: Sanity, Package Lists & System Auditing (F1, F2, F12)
  Tier 2: DNF4/DNF5 Compatibility & COPR Management (F3, F4, F5)
  Tier 3: Compositors & SDDM Display Manager Integration (F6, F7, F8, F9)
  Tier 4: systemd Services, Auto-Updates & Installer Bootstrap (F10, F11, F12)

Exit Codes:
  0 - All executed tests passed successfully
  1 - One or more tests failed
EOF
}

TARGET_TIER=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)
            TARGET_TIER="$2"
            shift 2
            ;;
        --tier=*)
            TARGET_TIER="${1#*=}"
            shift
            ;;
        --all)
            TARGET_TIER=""
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}       linka E2E Test Suite (Fedora Compatibility)    ${COLOR_RESET}"
echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
echo "Start time: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_SUITE_NAMES=()

run_suite() {
    local tier_num="$1"
    local suite_script="$2"
    local suite_desc="$3"

    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    echo -e "${COLOR_CYAN}--- Running Tier $tier_num: $suite_desc ---${COLOR_RESET}"

    local suite_rc=0
    if [[ "$VERBOSE" -eq 1 ]]; then
        "$TESTS_DIR/$suite_script" || suite_rc=$?
    else
        "$TESTS_DIR/$suite_script" || suite_rc=$?
    fi

    if [[ "$suite_rc" -eq 0 ]]; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo -e "${COLOR_GREEN}✓ Tier $tier_num PASSED${COLOR_RESET}"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        FAILED_SUITE_NAMES+=("Tier $tier_num: $suite_desc")
        echo -e "${COLOR_RED}✗ Tier $tier_num FAILED (exit code $suite_rc)${COLOR_RESET}"
    fi
    echo ""
}

case "$TARGET_TIER" in
    1)
        run_suite 1 "tier1_packages_audit.sh" "Sanity & Package Lists Audit"
        ;;
    2)
        run_suite 2 "tier2_dnf_copr.sh" "DNF4/DNF5 & COPR Compatibility"
        ;;
    3)
        run_suite 3 "tier3_compositors_sddm.sh" "Compositors & SDDM Integration"
        ;;
    4)
        run_suite 4 "tier4_services_auto_update.sh" "systemd Services & Auto-Updates"
        ;;
    "")
        run_suite 1 "tier1_packages_audit.sh" "Sanity & Package Lists Audit"
        run_suite 2 "tier2_dnf_copr.sh" "DNF4/DNF5 & COPR Compatibility"
        run_suite 3 "tier3_compositors_sddm.sh" "Compositors & SDDM Integration"
        run_suite 4 "tier4_services_auto_update.sh" "systemd Services & Auto-Updates"
        ;;
    *)
        echo -e "${COLOR_RED}Invalid tier '$TARGET_TIER'. Must be 1, 2, 3, or 4.${COLOR_RESET}" >&2
        exit 1
        ;;
esac

echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}                 FINAL TEST SUMMARY                   ${COLOR_RESET}"
echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
echo "Total Suites Executed: $TOTAL_SUITES"
echo -e "Passed Suites        : ${COLOR_GREEN}$PASSED_SUITES${COLOR_RESET}"

if [[ "$FAILED_SUITES" -gt 0 ]]; then
    echo -e "Failed Suites        : ${COLOR_RED}$FAILED_SUITES${COLOR_RESET}"
    echo "Failed suites list:"
    for s in "${FAILED_SUITE_NAMES[@]}"; do
        echo -e "  - ${COLOR_RED}$s${COLOR_RESET}"
    done
    echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
    echo -e "${COLOR_RED}RESULT: FAILED${COLOR_RESET}"
    exit 1
else
    echo -e "Failed Suites        : ${COLOR_GREEN}0${COLOR_RESET}"
    echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
    echo -e "${COLOR_GREEN}RESULT: ALL TESTS PASSED (100% SUCCESS)${COLOR_RESET}"
    exit 0
fi
