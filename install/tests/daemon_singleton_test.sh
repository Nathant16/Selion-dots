#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (expected='$expected', actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

TMP_ROOT="$(mktemp -d)"
SANDBOX_PIDS=()

cleanup_all() {
    local sb
    for sb in "$TMP_ROOT"/*; do
        [ -d "$sb/runtime/serpantinum" ] || continue
        SERPANTINUM_RUNTIME_DIR="$sb/runtime/serpantinum" \
        XDG_RUNTIME_DIR="$sb/runtime" \
        HOME="$sb/home" \
        MAIN_QML="$sb/Shell.qml" \
        SERPANTINUM_DIR="$REPO_ROOT/src" \
        PATH="$sb/bin:/usr/bin:/bin" \
        bash "$REPO_ROOT/bin/serpantinumd" stop >/dev/null 2>&1 || true
    done
    local p
    for p in "${SANDBOX_PIDS[@]:-}"; do
        [ -n "$p" ] && kill -KILL "$p" 2>/dev/null || true
    done
    rm -rf "$TMP_ROOT"
}
trap cleanup_all EXIT

setup_sandbox() {
    local name="$1"
    local sb="$TMP_ROOT/$name"
    mkdir -p "$sb/bin" "$sb/home/.config/serpantinum" "$sb/home/.local/state/serpantinum" "$sb/home/.cache/serpantinum" "$sb/runtime/serpantinum"
    printf '{}\n' > "$sb/home/.config/serpantinum/settings.json"
    : > "$sb/Shell.qml"
    : > "$sb/qs_started.log"
    : > "$sb/qs_ipc.log"
    touch "$sb/runtime/wayland-1"

    cat > "$sb/bin/quickshell" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *" ipc "* ]]; then
    echo "$*" >> "$QS_IPC_LOG"
    exit 0
fi
echo "$$" >> "$QS_STARTED_LOG"
trap 'exit 0' TERM INT HUP
while true; do sleep 0.2; done
EOF

    cat > "$sb/bin/serpantinum-core" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$sb/bin/serpantinum-audio" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$sb/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    cat > "$sb/bin/dbus-update-activation-environment" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$sb/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$sb/bin/serpantinum-gamma" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$sb/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    cat > "$sb/bin/pkill" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$sb/bin/dbus-send" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    cat > "$sb/bin/poweroff" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    cat > "$sb/bin/reboot" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

    chmod +x "$sb/bin/"*
    printf '%s\n' "$sb"
}

run_in_sb() {
    local sb="$1"
    shift
    env \
        HOME="$sb/home" \
        XDG_CONFIG_HOME="$sb/home/.config" \
        XDG_STATE_HOME="$sb/home/.local/state" \
        XDG_CACHE_HOME="$sb/home/.cache" \
        XDG_RUNTIME_DIR="$sb/runtime" \
        SERPANTINUM_RUNTIME_DIR="$sb/runtime/serpantinum" \
        SERPANTINUM_DIR="$REPO_ROOT/src" \
        MAIN_QML="$sb/Shell.qml" \
        QS_STARTED_LOG="$sb/qs_started.log" \
        QS_IPC_LOG="$sb/qs_ipc.log" \
        WAYLAND_DISPLAY="${SB_WAYLAND_DISPLAY:-wayland-1}" \
        DESKTOP_SESSION="hyprland" \
        XDG_CURRENT_DESKTOP="Hyprland" \
        HYPRLAND_INSTANCE_SIGNATURE="sig1" \
        PATH="$sb/bin:/usr/bin:/bin" \
        "$@"
}

count_sb_pids() {
    local sb="$1"
    local mode="$2"
    run_in_sb "$sb" bash -c '
        source "$SERPANTINUM_DIR/scripts/daemon_lock.sh"
        daemon_init_paths
        daemon_find_scoped_processes "'"$mode"'" | wc -l
    '
}

wait_for_qs_count() {
    local sb="$1"
    local expected="$2"
    local i=0
    while [ "$i" -lt 40 ]; do
        if [ "$(count_sb_pids "$sb" quickshell)" -eq "$expected" ] && [ -s "$sb/runtime/serpantinum/serpantinumd.pid" ]; then
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

# Test 1: Concurrent `serpantinumd start` launches strictly one daemon and one quickshell
SB1="$(setup_sandbox concurrent_start)"
for _ in 1 2 3 4 5; do
    run_in_sb "$SB1" bash "$REPO_ROOT/bin/serpantinumd" start >/dev/null 2>&1 &
    SANDBOX_PIDS+=($!)
done
wait_for_qs_count "$SB1" 1 || true
sleep 0.4
assert_eq "concurrent start launches only 1 quickshell" "1" "$(count_sb_pids "$SB1" quickshell)"
assert_eq "concurrent start leaves only 1 daemon" "1" "$(count_sb_pids "$SB1" daemon)"
assert_eq "quickshell started once" "1" "$(wc -l < "$SB1/qs_started.log" | tr -d ' ')"

INODE_BEFORE="$(stat -c '%i' "$SB1/runtime/serpantinum/serpantinumd.lock")"

# Test 2: Power/session scripts never delete serpantinumd.lock/.pid, and multiple `serpantinum msg` calls do not break flock or spawn extras
if grep -qE 'rm[[:space:]]+.*serpantinumd\.(lock|pid)' "$REPO_ROOT/src/scripts/system/exit.sh" "$REPO_ROOT/src/scripts/system/poweroff.sh" "$REPO_ROOT/src/scripts/system/reboot.sh"; then
    echo "FAIL: system power/exit scripts still remove serpantinumd.lock or serpantinumd.pid"
    FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

msg_pids=()
for _ in 1 2 3 4 5; do
    run_in_sb "$SB1" bash "$REPO_ROOT/bin/serpantinum" msg toggle launcher >/dev/null 2>&1 &
    msg_pids+=($!)
done
for p in "${msg_pids[@]}"; do
    wait "$p" || true
done
assert_eq "lock inode unchanged after static check and msg" "$INODE_BEFORE" "$(stat -c '%i' "$SB1/runtime/serpantinum/serpantinumd.lock")"
assert_eq "still 1 quickshell after static check and msg" "1" "$(count_sb_pids "$SB1" quickshell)"
assert_eq "quickshell still only started once" "1" "$(wc -l < "$SB1/qs_started.log" | tr -d ' ')"
assert_eq "all 5 ipc messages dispatched" "5" "$(wc -l < "$SB1/qs_ipc.log" | tr -d ' ')"

# Test 3: Stray duplicate quickshell cleanup on start & restart
run_in_sb "$SB1" "$SB1/bin/quickshell" -p "$SB1/Shell.qml" >/dev/null 2>&1 &
SANDBOX_PIDS+=($!)
run_in_sb "$SB1" "$SB1/bin/quickshell" -p "$SB1/Shell.qml" >/dev/null 2>&1 &
SANDBOX_PIDS+=($!)
sleep 0.2
assert_eq "pre-check spawned 2 extra stray quickshell processes" "3" "$(count_sb_pids "$SB1" quickshell)"

run_in_sb "$SB1" bash "$REPO_ROOT/bin/serpantinumd" restart >/dev/null 2>&1
wait_for_qs_count "$SB1" 1 || true
assert_eq "restart deduplicates down to 1 quickshell" "1" "$(count_sb_pids "$SB1" quickshell)"
assert_eq "restart keeps 1 daemon" "1" "$(count_sb_pids "$SB1" daemon)"

# Test 4: Stop cleans everything without deleting flock lock file
run_in_sb "$SB1" bash "$REPO_ROOT/bin/serpantinumd" stop >/dev/null 2>&1
assert_eq "stop leaves 0 quickshell processes" "0" "$(count_sb_pids "$SB1" quickshell)"
assert_eq "stop leaves 0 daemon processes" "0" "$(count_sb_pids "$SB1" daemon)"
assert_eq "stop preserves lock file inode" "$INODE_BEFORE" "$(stat -c '%i' "$SB1/runtime/serpantinum/serpantinumd.lock")"

# Test 5: Concurrent `bin/serpantinum msg` race from cold stopped state starts strictly 1 daemon
SB2="$(setup_sandbox cold_cli_race)"
cold_pids=()
for _ in 1 2 3 4 5; do
    run_in_sb "$SB2" bash "$REPO_ROOT/bin/serpantinum" msg toggle clipboard >/dev/null 2>&1 &
    cold_pids+=($!)
    SANDBOX_PIDS+=($!)
done
for p in "${cold_pids[@]}"; do
    wait "$p" || true
done
wait_for_qs_count "$SB2" 1 || true
sleep 0.3
assert_eq "cold ensure_daemon race starts only 1 quickshell" "1" "$(count_sb_pids "$SB2" quickshell)"
assert_eq "cold ensure_daemon race leaves only 1 daemon" "1" "$(count_sb_pids "$SB2" daemon)"
assert_eq "cold ensure_daemon race dispatches all 5 ipc calls" "5" "$(wc -l < "$SB2/qs_ipc.log" | tr -d ' ')"

# Test 6: Switching WAYLAND_DISPLAY replaces previous display's daemon cleanly
touch "$SB2/runtime/wayland-2"
SB_WAYLAND_DISPLAY="wayland-2" run_in_sb "$SB2" bash "$REPO_ROOT/bin/serpantinumd" start >/dev/null 2>&1 &
SANDBOX_PIDS+=($!)
SB_WAYLAND_DISPLAY="wayland-2" wait_for_qs_count "$SB2" 1 || true
sleep 0.3
assert_eq "new display has 1 quickshell" "1" "$(SB_WAYLAND_DISPLAY="wayland-2" count_sb_pids "$SB2" quickshell)"
assert_eq "old display wayland-1 daemon stopped cleanly" "0" "$(SB_WAYLAND_DISPLAY="wayland-1" count_sb_pids "$SB2" quickshell)"

echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
