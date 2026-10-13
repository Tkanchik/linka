#!/usr/bin/env bash
# ==============================================================================
# linka E2E Test Framework
# Provides assertion primitives, environment isolation, and test runner harness.
# ==============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"
MOCK_BIN_DIR="$TESTS_DIR/mock_bin"
LINKA_SCRIPT="$REPO_ROOT/linka"

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

# Global test accounting
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
FAILED_TEST_NAMES=()

# Per-test temporary environment paths
TEST_TMPDIR=""
ORIG_PATH="$PATH"
ORIG_HOME="$HOME"

# ------------------------------------------------------------------------------
# Test Environment Setup & Teardown
# ------------------------------------------------------------------------------

setup_test_env() {
    TEST_TMPDIR="$(mktemp -d -t linka_test_XXXXXX)"

    export MOCK_ROOT="$TEST_TMPDIR/root"
    export MOCK_LOGS="$TEST_TMPDIR/logs"
    export MOCK_DNF_STATE="$TEST_TMPDIR/dnf_state"
    export MOCK_RPM_STATE="$TEST_TMPDIR/rpm_state"
    export MOCK_SYSTEMCTL_STATE="$TEST_TMPDIR/systemctl_state"

    mkdir -p "$MOCK_ROOT/etc/sddm.conf.d" \
             "$MOCK_ROOT/usr/share/sddm/themes" \
             "$MOCK_ROOT/usr/local/bin" \
             "$MOCK_LOGS" \
             "$MOCK_DNF_STATE" \
             "$MOCK_RPM_STATE" \
             "$MOCK_SYSTEMCTL_STATE"

    # Isolated Home & XDG paths
    export HOME="$TEST_TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_RUNTIME_DIR="$TEST_TMPDIR/runtime"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"

    # Fake os-release for Fedora 41
    cat <<'EOF' > "$TEST_TMPDIR/os-release"
NAME="Fedora Linux"
VERSION="41 (Workstation Edition)"
ID=fedora
VERSION_ID=41
PLATFORM_ID="platform:f41"
PRETTY_NAME="Fedora Linux 41 (Workstation Edition)"
EOF
    export LINKA_OS_RELEASE="$TEST_TMPDIR/os-release"
    export LINKA_INIT_SYSTEM="systemd"

    # Prepend mock binaries to PATH
    export PATH="$MOCK_BIN_DIR:$ORIG_PATH"

    # Default mock environment variables
    export MOCK_DNF_VERSION="5"
    export MOCK_COPR_PLUGIN_ENABLED="1"
    echo "1" > "$MOCK_DNF_STATE/copr_plugin_active"
    export MOCK_DNF_CHECK_UPDATE_EXIT_CODE=0
    export MOCK_RPM_INSTALLED_PKGS=""
    export MOCK_RPM_PROVIDES=""
    export MOCK_SYSTEMD_USER_UNITS="pipewire.service wireplumber.service"
    export MOCK_SYSTEMD_SYSTEM_UNITS="NetworkManager.service"
    export MOCK_DM_LINK=""
}

teardown_test_env() {
    export PATH="$ORIG_PATH"
    export HOME="$ORIG_HOME"
    if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# ------------------------------------------------------------------------------
# Assertion Primitives
# ------------------------------------------------------------------------------

assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-Assertion failed: expected '$expected', got '$actual'}"

    if [[ "$actual" != "$expected" ]]; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        echo "  Expected: '$expected'" >&2
        echo "  Actual  : '$actual'" >&2
        return 1
    fi
    return 0
}

assert_ne() {
    local actual="$1"
    local not_expected="$2"
    local msg="${3:-Assertion failed: expected value to differ from '$not_expected'}"

    if [[ "$actual" == "$not_expected" ]]; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        echo "  Value was: '$actual'" >&2
        return 1
    fi
    return 0
}

assert_match() {
    local pattern="$1"
    local text="$2"
    local msg="${3:-Assertion failed: text does not match pattern '$pattern'}"

    if ! grep -qE "$pattern" <<< "$text"; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        echo "  Pattern: $pattern" >&2
        echo "  Text   : $text" >&2
        return 1
    fi
    return 0
}

assert_not_match() {
    local pattern="$1"
    local text="$2"
    local msg="${3:-Assertion failed: text unexpectedly matches pattern '$pattern'}"

    if grep -qE "$pattern" <<< "$text"; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        echo "  Forbidden Pattern: $pattern" >&2
        echo "  Text             : $text" >&2
        return 1
    fi
    return 0
}

assert_file_exists() {
    local path="$1"
    local msg="${2:-Assertion failed: expected file '$path' to exist}"

    if [[ ! -e "$path" ]]; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    local path="$1"
    local msg="${2:-Assertion failed: expected file '$path' not to exist}"

    if [[ -e "$path" ]]; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        return 1
    fi
    return 0
}

assert_file_contains() {
    local path="$1"
    local pattern="$2"
    local msg="${3:-Assertion failed: file '$path' does not contain pattern '$pattern'}"

    if [[ ! -f "$path" ]]; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} File '$path' does not exist" >&2
        return 1
    fi

    if ! grep -qE "$pattern" "$path"; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        echo "  Pattern     : $pattern" >&2
        echo "  File Content:" >&2
        cat "$path" >&2
        return 1
    fi
    return 0
}

assert_file_not_contains() {
    local path="$1"
    local pattern="$2"
    local msg="${3:-Assertion failed: file '$path' unexpectedly contains pattern '$pattern'}"

    if [[ ! -f "$path" ]]; then
        return 0
    fi

    if grep -qE "$pattern" "$path"; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        echo "  Pattern: $pattern" >&2
        return 1
    fi
    return 0
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Assertion failed: expected exit code $expected, got $actual}"

    if [[ "$actual" -ne "$expected" ]]; then
        echo -e "${COLOR_RED}FAIL:${COLOR_RESET} $msg" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Test Execution Harness
# ------------------------------------------------------------------------------

run_test() {
    local test_name="$1"
    local test_fn="$2"
    local test_feature="${3:-}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    local feat_tag=""
    if [[ -n "$test_feature" ]]; then
        feat_tag="[${COLOR_CYAN}$test_feature${COLOR_RESET}] "
    fi

    echo -ne "  ${feat_tag}${test_name} ... "

    # Execute test in isolated subshell
    local test_output
    local test_rc=0
    test_output=$(
        setup_test_env
        trap 'teardown_test_env' EXIT
        # Run test function
        "$test_fn"
    ) || test_rc=$?

    if [[ "$test_rc" -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${COLOR_GREEN}PASS${COLOR_RESET}"
    elif [[ "$test_rc" -eq 77 ]]; then
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        echo -e "${COLOR_YELLOW}SKIP${COLOR_RESET}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TEST_NAMES+=("$test_name")
        echo -e "${COLOR_RED}FAIL${COLOR_RESET} (exit code $test_rc)"
        if [[ -n "$test_output" ]]; then
            sed 's/^/    /' <<< "$test_output"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Suite Summary
# ------------------------------------------------------------------------------

print_suite_summary() {
    local suite_name="$1"
    echo ""
    echo -e "${COLOR_BOLD}=== Summary: $suite_name ===${COLOR_RESET}"
    echo "  Total Tests: $TESTS_TOTAL"
    echo -e "  Passed     : ${COLOR_GREEN}$TESTS_PASSED${COLOR_RESET}"
    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        echo -e "  Failed     : ${COLOR_RED}$TESTS_FAILED${COLOR_RESET}"
        echo "  Failed tests list:"
        for f in "${FAILED_TEST_NAMES[@]}"; do
            echo -e "    - ${COLOR_RED}$f${COLOR_RESET}"
        done
    else
        echo -e "  Failed     : ${COLOR_GREEN}0${COLOR_RESET}"
    fi
    if [[ "$TESTS_SKIPPED" -gt 0 ]]; then
        echo -e "  Skipped    : ${COLOR_YELLOW}$TESTS_SKIPPED${COLOR_RESET}"
    fi
    echo "=========================================="
    echo ""

    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        return 1
    fi
    return 0
}
