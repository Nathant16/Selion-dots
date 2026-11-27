#!/usr/bin/env bash

restart_daemon_if_running() {
    local name="$1" pattern="$2" pids pid count
    shift 2
    command -v "$name" >/dev/null 2>&1 || return 0
    pids="$(pgrep -u "$(id -u)" -f "$pattern" 2>/dev/null)" || return 0
    "$name" "$@" >/dev/null 2>&1 || true
    for pid in $pids; do
        count=0
        while kill -0 "$pid" 2>/dev/null && [ "$count" -lt 40 ]; do
            sleep 0.05
            count=$((count + 1))
        done
    done
    "$name" start >/dev/null 2>&1 || true
}

restart_serpantinumd_if_running() {
    local target_base="${1:-$HOME/.local/share/serpantinum}"
    local daemon_bin="$target_base/bin/serpantinumd"
    [ -x "$daemon_bin" ] || return 0
    [ -n "${WAYLAND_DISPLAY:-}" ] || return 0
    local uid
    uid="$(id -u)"
    if pgrep -u "$uid" -f "$target_base/(bin/serpantinumd|src/quickshell/Shell\\.qml)" >/dev/null 2>&1; then
        env -u SERPANTINUM_DIR -u SERPANTINUM_INSTALLER -u MAIN_QML -u QS_DIR -u I18N_DIR \
            -u QS_CACHE_DIR -u QS_STATE_DIR -u QS_RUN_DIR -u QS_LOG_DIR \
            -u SUDO_PROMPT -u SERP_FAILED_PKGS_FILE -u PROJECT_ROOT -u MODULES_DIR -u REPO_SLUG \
            -u INSTALL_STATE -u OLD_VERSION -u TARGET_VERSION -u OLD_COMMIT -u TARGET_COMMIT \
            -u TELEMETRY_ID -u ENABLE_TELEMETRY -u OPT_SDDM -u REPLACE_DM -u SDDM_WAYLAND \
            -u INSTALL_FULL_WALLPAPERS -u IS_REINSTALL -u DO_UNINSTALL \
            -u SELECTED_COMPOSITORS_STR -u SELECTED_ADDITIONAL_PKGS_STR \
            -u KEYBOARD_LAYOUT -u KEYBOARD_TOGGLE -u OPT_FAST_REPOS \
            "$daemon_bin" restart </dev/null >/dev/null 2>&1 || true
    fi
}
