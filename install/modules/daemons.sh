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
        "$daemon_bin" restart </dev/null >/dev/null 2>&1 || true
    fi
}
