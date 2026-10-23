#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS %s\n' "$1"; }

test_operation_summary() (
    local fixture output
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    mkdir -p "$STATE_DIR" "$BACKUP_BASE/snapshot"
    printf '%s\n' "$BACKUP_BASE/snapshot" > "$STATE_DIR/.last-update-backup"
    touch "$STATE_DIR/.linka-journal"
    output="$(linka_operation_summary update 1)"
    [[ "$output" == *'Обновление: ошибка'* ]] || fail operation_summary
    [[ "$output" == *"Бэкап: $BACKUP_BASE/snapshot"* ]] || fail operation_summary
    [[ "$output" == *"Журнал: $STATE_DIR/.linka-journal"* ]] || fail operation_summary
    [[ "$output" == *'Пропущено:'* ]] || fail operation_summary
    pass operation_summary
)

test_backup_failure_preserves_pointer() (
    local fixture
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$BACKUP_BASE"
    printf 'user data\n' > "$CONFIG_DIR/settings.json"
    printf 'previous\n' > "$STATE_DIR/.last-update-backup"
    cp() { return 1; }
    if backup_update_state; then fail backup_failure_preserves_pointer; fi
    [[ "$(cat "$STATE_DIR/.last-update-backup")" == previous ]] || fail backup_failure_preserves_pointer
    [[ -z "$UPDATE_BACKUP_DIR" ]] || fail backup_failure_preserves_pointer
    pass backup_failure_preserves_pointer
)

test_backup_roundtrip() (
    local fixture
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    mkdir -p "$CONFIG_DIR" "$STATE_DIR/sounds"
    printf 'old config\n' > "$CONFIG_DIR/settings.json"
    printf 'old sound\n' > "$STATE_DIR/sounds/user.wav"
    printf 'old state\n' > "$STATE_DIR/state"
    backup_update_state || fail backup_roundtrip
    [[ -f "$UPDATE_BACKUP_DIR/.complete" ]] || fail backup_roundtrip
    [[ "$(cat "$UPDATE_BACKUP_DIR/config/settings.json")" == 'old config' ]] || fail backup_roundtrip
    [[ "$(cat "$UPDATE_BACKUP_DIR/state/state")" == 'old state' ]] || fail backup_roundtrip
    printf 'new config\n' > "$CONFIG_DIR/settings.json"
    printf 'new sound\n' > "$STATE_DIR/sounds/user.wav"
    printf 'added\n' > "$CONFIG_DIR/added.json"
    printf 'added\n' > "$STATE_DIR/sounds/added.wav"
    printf 'added\n' > "$STATE_DIR/added-state"
    restore_update_config || fail backup_roundtrip
    restore_update_sounds || fail backup_roundtrip
    restore_update_state || fail backup_roundtrip
    [[ "$(cat "$CONFIG_DIR/settings.json")" == 'old config' ]] || fail backup_roundtrip
    [[ "$(cat "$STATE_DIR/sounds/user.wav")" == 'old sound' ]] || fail backup_roundtrip
    [[ ! -e "$CONFIG_DIR/added.json" && ! -e "$STATE_DIR/sounds/added.wav" && ! -e "$STATE_DIR/added-state" ]] || fail backup_roundtrip
    pass backup_roundtrip
)

test_autounmask_write_failure_keeps_pending() (
    local fixture cfg
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture" PORTAGE_ROOT="$fixture/portage"
    source "$ROOT/linka"
    mkdir -p "$PORTAGE_ROOT/package.use"
    printf 'existing\n' > "$PORTAGE_ROOT/package.use/serpantinum"
    cfg="$PORTAGE_ROOT/package.use/._cfg0000_serpantinum"
    printf 'new flag\n' > "$cfg"
    run_root() {
        if [[ "$1" == tee ]]; then return 1; fi
        "$@"
    }
    if gentoo_apply_autounmask_cfg "$cfg"; then fail autounmask_write_failure_keeps_pending; fi
    [[ -f "$cfg" ]] || fail autounmask_write_failure_keeps_pending
    [[ "$(cat "$PORTAGE_ROOT/package.use/serpantinum")" == existing ]] || fail autounmask_write_failure_keeps_pending
    pass autounmask_write_failure_keeps_pending
)

test_autounmask_only_current_and_idempotent() (
    local fixture cfg old
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture" PORTAGE_ROOT="$fixture/portage"
    source "$ROOT/linka"
    mkdir -p "$PORTAGE_ROOT/package.use"
    printf 'existing\n' > "$PORTAGE_ROOT/package.use/serpantinum"
    cfg="$PORTAGE_ROOT/package.use/._cfg0001_serpantinum"
    old="$PORTAGE_ROOT/package.use/._cfg0000_unrelated"
    printf 'new flag\n' > "$cfg"
    printf 'unrelated\n' > "$old"
    run_root() { "$@"; }
    gentoo_apply_autounmask_cfg "$cfg" || fail autounmask_only_current_and_idempotent
    [[ -f "$old" ]] || fail autounmask_only_current_and_idempotent
    [[ ! -e "$cfg" ]] || fail autounmask_only_current_and_idempotent
    [[ "$(cat "$PORTAGE_ROOT/package.use/serpantinum")" == $'existing\nnew flag' ]] || fail autounmask_only_current_and_idempotent
    pass autounmask_only_current_and_idempotent
)

test_autounmask_leaves_preexisting_pending_file() (
    local fixture old
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture" PORTAGE_ROOT="$fixture/portage"
    source "$ROOT/linka"
    mkdir -p "$PORTAGE_ROOT/package.use"
    old="$PORTAGE_ROOT/package.use/._cfg0000_unrelated"
    printf 'unrelated\n' > "$old"
    printf 'existing\n' > "$PORTAGE_ROOT/package.use/serpantinum"
    emerge() {
        if [[ " $* " == *' --autounmask-write=y '* ]]; then
            printf 'new flag\n' > "$PORTAGE_ROOT/package.use/._cfg0001_serpantinum"
            return 1
        fi
        [[ "$(cat "$PORTAGE_ROOT/package.use/serpantinum")" == *'new flag'* ]]
    }
    run_root() { "$@"; }
    gentoo_autounmask_resolve gui-apps/quickshell || fail autounmask_leaves_preexisting_pending_file
    [[ -f "$old" ]] || fail autounmask_leaves_preexisting_pending_file
    [[ "$(cat "$PORTAGE_ROOT/package.use/serpantinum")" == $'existing\nnew flag' ]] || fail autounmask_leaves_preexisting_pending_file
    pass autounmask_leaves_preexisting_pending_file
)

test_autounmask_retry_does_not_duplicate_lines() (
    local fixture cfg
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture" PORTAGE_ROOT="$fixture/portage"
    source "$ROOT/linka"
    mkdir -p "$PORTAGE_ROOT/package.use"
    cfg="$PORTAGE_ROOT/package.use/._cfg0001_serpantinum"
    printf 'existing\n' > "$PORTAGE_ROOT/package.use/serpantinum"
    printf 'new flag\n' > "$cfg"
    run_root() {
        if [[ "$1" == rm && "${*: -1}" == "$cfg" ]]; then return 1; fi
        "$@"
    }
    if gentoo_apply_autounmask_cfg "$cfg"; then fail autounmask_retry_does_not_duplicate_lines; fi
    run_root() { "$@"; }
    gentoo_apply_autounmask_cfg "$cfg" || fail autounmask_retry_does_not_duplicate_lines
    [[ "$(cat "$PORTAGE_ROOT/package.use/serpantinum")" == $'existing\nnew flag' ]] || fail autounmask_retry_does_not_duplicate_lines
    [[ ! -e "$cfg" ]] || fail autounmask_retry_does_not_duplicate_lines
    pass autounmask_retry_does_not_duplicate_lines
)

test_required_dependency_blocks_deploy() (
    local fixture
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    DISTRO=fedora
    CORE_PKGS=(qt6-qtmultimedia)
    pkg_installed() { return 1; }
    is_compositor_installed() { return 0; }
    check_quickshell() { return 0; }
    if verify_required_dependencies hyprland; then fail required_dependency_blocks_deploy; fi
    pass required_dependency_blocks_deploy
)

test_unknown_quickshell_version_blocks_deploy() (
    local fixture
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    quickshell_version() { printf '\n'; }
    if check_quickshell; then fail unknown_quickshell_version_blocks_deploy; fi
    pass unknown_quickshell_version_blocks_deploy
)

test_type_change_deploys_symlink() (
    local fixture repo old middle
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    repo="$fixture/repo"
    mkdir -p "$repo/src" "$TARGET_BASE/src"
    git -C "$fixture" init -q repo
    git -C "$repo" config user.name QA
    git -C "$repo" config user.email qa@example.invalid
    printf 'old\n' > "$repo/src/item"
    git -C "$repo" add .
    git -C "$repo" commit -qm old
    old="$(git -C "$repo" rev-parse HEAD)"
    cp "$repo/src/item" "$TARGET_BASE/src/item"
    printf 'new\n' > "$repo/src/target"
    rm "$repo/src/item"
    ln -s target "$repo/src/item"
    git -C "$repo" add -A
    git -C "$repo" commit -qm new
    deploy_incremental "$repo" "$old" || fail type_change_deploys_symlink
    [[ -L "$TARGET_BASE/src/item" ]] || fail type_change_deploys_symlink
    [[ "$(readlink "$TARGET_BASE/src/item")" == target ]] || fail type_change_deploys_symlink
    middle="$(git -C "$repo" rev-parse HEAD)"
    rm "$repo/src/item"
    printf 'ordinary\n' > "$repo/src/item"
    git -C "$repo" add -A
    git -C "$repo" commit -qm ordinary
    deploy_incremental "$repo" "$middle" || fail type_change_deploys_symlink
    [[ -f "$TARGET_BASE/src/item" && ! -L "$TARGET_BASE/src/item" ]] || fail type_change_deploys_symlink
    [[ "$(cat "$TARGET_BASE/src/item")" == ordinary ]] || fail type_change_deploys_symlink
    pass type_change_deploys_symlink
)

test_failed_start_restores_previous_generation() (
    local fixture repo
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    repo="$fixture/repo"
    mkdir -p "$repo/bin" "$repo/src/quickshell" "$TARGET_BASE/src/quickshell" "$CONFIG_DIR" "$STATE_DIR"
    git -C "$fixture" init -q repo
    git -C "$repo" config user.name QA
    git -C "$repo" config user.email qa@example.invalid
    printf '#!/bin/sh\nexit 0\n' > "$repo/bin/serpantinumd"
    printf '#!/bin/sh\nexit 0\n' > "$repo/bin/serpantinum"
    chmod +x "$repo/bin/serpantinumd" "$repo/bin/serpantinum"
    printf 'new\n' > "$repo/src/quickshell/main.qml"
    git -C "$repo" add .
    git -C "$repo" commit -qm new
    printf 'old\n' > "$TARGET_BASE/src/quickshell/main.qml"
    printf 'old state\n' > "$STATE_FILE"
    printf 'old config\n' > "$CONFIG_DIR/settings.json"
    OLD_VERSION=old OLD_COMMIT=old TARGET_VERSION=new TARGET_COMMIT=new
    shell_running() { return 0; }
    stop_shell() { return 0; }
    start_shell() { return 1; }
    start_shell_unless_idle() { return 1; }
    run_user_post_update_hook() { return 0; }
    fix_matugen_compat() { return 0; }
    sync_sounds_from_repo() { return 0; }
    merge_serpantinum_config() { return 0; }
    declare -F transactional_deploy_update >/dev/null || fail failed_start_restores_previous_generation
    if transactional_deploy_update "$repo"; then fail failed_start_restores_previous_generation; fi
    [[ "$(cat "$TARGET_BASE/src/quickshell/main.qml")" == old ]] || fail failed_start_restores_previous_generation
    [[ "$(cat "$STATE_FILE")" == 'old state' ]] || fail failed_start_restores_previous_generation
    [[ "$(cat "$CONFIG_DIR/settings.json")" == 'old config' ]] || fail failed_start_restores_previous_generation
    pass failed_start_restores_previous_generation
)

test_backup_failure_does_not_stop_shell() (
    local fixture repo
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    repo="$fixture/repo"
    mkdir -p "$repo/bin" "$repo/src/quickshell" "$TARGET_BASE/src/quickshell"
    git -C "$fixture" init -q repo
    git -C "$repo" config user.name QA
    git -C "$repo" config user.email qa@example.invalid
    printf '#!/bin/sh\nexit 0\n' > "$repo/bin/serpantinumd"
    chmod +x "$repo/bin/serpantinumd"
    printf 'new\n' > "$repo/src/quickshell/main.qml"
    git -C "$repo" add .
    git -C "$repo" commit -qm new
    printf 'old\n' > "$TARGET_BASE/src/quickshell/main.qml"
    run_user_post_update_hook() { return 0; }
    fix_matugen_compat() { return 0; }
    backup_update_state() { return 1; }
    stop_shell() { : > "$fixture/stopped"; return 0; }
    if transactional_deploy_update "$repo"; then fail backup_failure_does_not_stop_shell; fi
    [[ ! -e "$fixture/stopped" ]] || fail backup_failure_does_not_stop_shell
    [[ "$(cat "$TARGET_BASE/src/quickshell/main.qml")" == old ]] || fail backup_failure_does_not_stop_shell
    pass backup_failure_does_not_stop_shell
)

test_success_then_manual_rollback() (
    local fixture repo
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    repo="$fixture/repo"
    mkdir -p "$repo/bin" "$repo/src/quickshell" "$TARGET_BASE/src/quickshell" "$CONFIG_DIR" "$STATE_DIR"
    git -C "$fixture" init -q repo
    git -C "$repo" config user.name QA
    git -C "$repo" config user.email qa@example.invalid
    printf '#!/bin/sh\nexit 0\n' > "$repo/bin/serpantinumd"
    printf '#!/bin/sh\nexit 0\n' > "$repo/bin/serpantinum"
    chmod +x "$repo/bin/serpantinumd" "$repo/bin/serpantinum"
    printf 'new\n' > "$repo/src/quickshell/main.qml"
    git -C "$repo" add .
    git -C "$repo" commit -qm new
    printf 'old\n' > "$TARGET_BASE/src/quickshell/main.qml"
    printf 'old state\n' > "$STATE_FILE"
    printf 'old config\n' > "$CONFIG_DIR/settings.json"
    mkdir -p "$CONFIG_DIR/hooks"
    printf '#!/bin/sh\nprintf "custom\\n" > "$TARGET_DIR/src/custom-widget"\n' > "$CONFIG_DIR/hooks/post_update.sh"
    chmod +x "$CONFIG_DIR/hooks/post_update.sh"
    OLD_VERSION=old OLD_COMMIT=old TARGET_VERSION=new TARGET_COMMIT=new
    shell_running() { return 0; }
    stop_shell() { return 0; }
    start_shell() { return 0; }
    start_shell_unless_idle() { return 0; }
    linka_health_check() { return 0; }
    fix_matugen_compat() { return 0; }
    sync_sounds_from_repo() { return 0; }
    merge_serpantinum_config() { return 0; }
    transactional_deploy_update "$repo" || fail success_then_manual_rollback
    [[ "$(cat "$TARGET_BASE/src/quickshell/main.qml")" == new ]] || fail success_then_manual_rollback
    [[ -f "$TARGET_BASE/src/custom-widget" ]] || fail success_then_manual_rollback
    [[ "$(state_get SHELL_COMMIT)" == new ]] || fail success_then_manual_rollback
    linka_rollback || fail success_then_manual_rollback
    [[ "$(cat "$TARGET_BASE/src/quickshell/main.qml")" == old ]] || fail success_then_manual_rollback
    [[ ! -e "$TARGET_BASE/src/custom-widget" ]] || fail success_then_manual_rollback
    [[ "$(cat "$STATE_FILE")" == 'old state' ]] || fail success_then_manual_rollback
    [[ "$(cat "$CONFIG_DIR/settings.json")" == 'old config' ]] || fail success_then_manual_rollback
    pass success_then_manual_rollback
)

test_headless_update_refused() (
    local fixture
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    unset WAYLAND_DISPLAY XDG_RUNTIME_DIR
    auto_adopt_session_env() { return 0; }
    if linka_update_session_ready; then fail headless_update_refused; fi
    pass headless_update_refused
)

test_diagnostics_are_read_only() (
    local fixture report
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    DISTRO=fedora
    CORE_PKGS=(qt6-qtdeclarative)
    pkg_installed() { return 1; }
    report="$(linka_doctor)" || true
    [[ "$report" == *qt6-qtdeclarative* ]] || fail diagnostics_are_read_only
    [[ ! -e "$STATE_DIR" && ! -e "$TARGET_BASE" ]] || fail diagnostics_are_read_only
    pass diagnostics_are_read_only
)

test_update_dry_run_skips_preparation() (
    local fixture report
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    DISTRO=fedora
    CORE_PKGS=()
    prepare_environment() { fail update_dry_run_skips_preparation; }
    report="$(main update --dry-run)" || fail update_dry_run_skips_preparation
    [[ "$report" == *'Изменений не внесено.'* ]] || fail update_dry_run_skips_preparation
    report="$(main --update --dry-run)" || fail update_dry_run_skips_preparation
    [[ "$report" == *'Изменений не внесено.'* ]] || fail update_dry_run_skips_preparation
    [[ ! -e "$STATE_DIR" && ! -e "$TARGET_BASE" ]] || fail update_dry_run_skips_preparation
    pass update_dry_run_skips_preparation
)

test_interrupted_switch_recovers_previous_generation() (
    local fixture previous next
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    previous="$GENERATIONS_BASE/previous.fixture"
    next="$GENERATIONS_BASE/generation.fixture"
    mkdir -p "$previous/src" "$next/src" "$CONFIG_DIR" "$STATE_DIR"
    printf 'old\n' > "$previous/src/item"
    printf 'new\n' > "$next/src/item"
    printf 'old state\n' > "$STATE_FILE"
    backup_update_state || fail interrupted_switch_recovers_previous_generation
    ln -s "$next" "$TARGET_BASE"
    printf 'new state\n' > "$STATE_FILE"
    shell_running() { return 1; }
    stop_shell() { return 0; }
    linka_journal_write "$previous" "$next" "$UPDATE_BACKUP_DIR" 0 || fail interrupted_switch_recovers_previous_generation
    linka_recover_transaction || fail interrupted_switch_recovers_previous_generation
    [[ "$(cat "$TARGET_BASE/src/item")" == old ]] || fail interrupted_switch_recovers_previous_generation
    [[ "$(cat "$STATE_FILE")" == 'old state' ]] || fail interrupted_switch_recovers_previous_generation
    [[ ! -e "$STATE_DIR/.linka-journal" ]] || fail interrupted_switch_recovers_previous_generation
    pass interrupted_switch_recovers_previous_generation
)

test_config_symlink_target_untouched() (
    local fixture external
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    external="$fixture/external"
    mkdir -p "$external" "$BACKUP_BASE/update.fixture/config"
    printf 'keep\n' > "$external/settings.json"
    printf 'replace\n' > "$BACKUP_BASE/update.fixture/config/settings.json"
    : > "$BACKUP_BASE/update.fixture/.complete"
    mkdir -p "${CONFIG_DIR%/*}"
    ln -s "$external" "$CONFIG_DIR"
    UPDATE_BACKUP_DIR="$BACKUP_BASE/update.fixture"
    if restore_update_config; then fail config_symlink_target_untouched; fi
    [[ "$(cat "$external/settings.json")" == keep ]] || fail config_symlink_target_untouched
    pass config_symlink_target_untouched
)

test_failed_rollback_keeps_recoverable_generation() (
    local fixture previous current backup
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    previous="$GENERATIONS_BASE/previous.fixture"
    current="$GENERATIONS_BASE/generation.fixture"
    backup="$BACKUP_BASE/update.fixture"
    mkdir -p "$previous/src" "$current/src" "$backup/config" "$backup/sounds" "$backup/state" "$STATE_DIR"
    printf 'old\n' > "$previous/src/item"
    printf 'new\n' > "$current/src/item"
    printf 'old state\n' > "$backup/state/state"
    : > "$backup/.complete"
    ln -s "$current" "$TARGET_BASE"
    printf 'new state\n' > "$STATE_FILE"
    printf '%s\n%s\n' "$previous" "$backup" > "$STATE_DIR/.linka-rollback"
    shell_running() { return 1; }
    stop_shell() { return 0; }
    restore_update_config() { return 1; }
    if linka_rollback; then fail failed_rollback_keeps_recoverable_generation; fi
    [[ "$(cat "$TARGET_BASE/src/item")" == old ]] || fail failed_rollback_keeps_recoverable_generation
    [[ -f "$STATE_DIR/.linka-journal" ]] || fail failed_rollback_keeps_recoverable_generation
    [[ "$(sed -n '1p' "$STATE_DIR/.linka-journal")" == "$previous" ]] || fail failed_rollback_keeps_recoverable_generation
    pass failed_rollback_keeps_recoverable_generation
)

test_install_recovers_before_mutation() (
    local fixture
    fixture="$(mktemp -d)"
    trap 'rm -rf -- "$fixture"' EXIT
    export HOME="$fixture"
    source "$ROOT/linka"
    linka_recover_transaction() { : > "$fixture/recovery-attempted"; return 1; }
    detect_install_state() { : > "$fixture/install-state-read"; printf 'current\n'; }
    load_state() { fail install_recovers_before_mutation; }
    if flow_install install; then fail install_recovers_before_mutation; fi
    [[ -f "$fixture/recovery-attempted" ]] || fail install_recovers_before_mutation
    pass install_recovers_before_mutation
)

test_backup_failure_preserves_pointer
test_backup_roundtrip
test_autounmask_write_failure_keeps_pending
test_autounmask_only_current_and_idempotent
test_autounmask_leaves_preexisting_pending_file
test_autounmask_retry_does_not_duplicate_lines
test_required_dependency_blocks_deploy
test_unknown_quickshell_version_blocks_deploy
test_type_change_deploys_symlink
test_failed_start_restores_previous_generation
test_backup_failure_does_not_stop_shell
test_success_then_manual_rollback
test_headless_update_refused
test_diagnostics_are_read_only
test_update_dry_run_skips_preparation
test_interrupted_switch_recovers_previous_generation
test_config_symlink_target_untouched
test_failed_rollback_keeps_recoverable_generation
test_install_recovers_before_mutation
test_operation_summary
