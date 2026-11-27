#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXIT_SCRIPT="$REPO_ROOT/src/scripts/system/exit.sh"
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

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (unexpected '$needle' in '$haystack')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (missing '$needle' in '$haystack')"
        FAIL=$((FAIL + 1))
    fi
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

setup_mock_env() {
    local name="$1"
    local polls_until_exit="$2"
    local sb="$TMP_ROOT/$name"
    mkdir -p "$sb/bin" "$sb/runtime/hypr/sig1"
    : > "$sb/log"
    printf '0\n' > "$sb/polls"
    printf '%s\n' "$polls_until_exit" > "$sb/limit"

    cat > "$sb/bin/hyprctl" <<EOF
#!/usr/bin/env bash
echo "hyprctl \$*" >> "$sb/log"
exit 0
EOF
    cat > "$sb/bin/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >> "$sb/log"
exit 0
EOF
    cat > "$sb/bin/loginctl" <<EOF
#!/usr/bin/env bash
echo "loginctl \$*" >> "$sb/log"
exit 0
EOF
    cat > "$sb/bin/pkill" <<EOF
#!/usr/bin/env bash
echo "pkill \$*" >> "$sb/log"
exit 0
EOF
    cat > "$sb/bin/uwsm" <<EOF
#!/usr/bin/env bash
exit 1
EOF
    cat > "$sb/bin/hyprshutdown" <<EOF
#!/usr/bin/env bash
exit 1
EOF
    cat > "$sb/bin/dinitctl" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    cat > "$sb/bin/sleep" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    cat > "$sb/bin/pgrep" <<EOF
#!/usr/bin/env bash
proc=""
for arg in "\$@"; do
    proc="\$arg"
done
if [[ "\$proc" != "Hyprland" && "\$proc" != "start-hyprland" ]]; then
    exit 1
fi
count=\$(cat "$sb/polls")
limit=\$(cat "$sb/limit")
if [[ "\$proc" == "Hyprland" ]]; then
    count=\$((count + 1))
    printf '%s\n' "\$count" > "$sb/polls"
fi
if [ "\$count" -le "\$limit" ]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$sb/bin/"*
    printf '%s\n' "$sb"
}

# Case 1: Hyprland takes 8 polls (0.8s > old 0.2s) to exit cleanly -> NO pkill, NO loginctl!
SB1="$(setup_mock_env graceful_slow 8)"
mkdir -p "$SB1/runtime/serpantinum"
: > "$SB1/runtime/serpantinum/serpantinumd.lock"
printf '999999\n' > "$SB1/runtime/serpantinum/serpantinumd.pid"
PATH="$SB1/bin:/usr/bin:/bin" \
XDG_RUNTIME_DIR="$SB1/runtime" \
SERPANTINUM_RUNTIME_DIR="$SB1/runtime/serpantinum" \
DESKTOP_SESSION="hyprland" \
XDG_CURRENT_DESKTOP="Hyprland" \
HYPRLAND_INSTANCE_SIGNATURE="sig1" \
XDG_SESSION_ID="2" \
bash "$EXIT_SCRIPT" hyprland

LOG1="$(cat "$SB1/log")"
assert_contains "graceful exit sends hl.dsp.exit()" "hyprctl dispatch hl.dsp.exit()" "$LOG1"
assert_contains "systemd user stop is non-blocking" "systemctl --user stop --no-block graphical-session.target graphical-session-pre.target" "$LOG1"
assert_not_contains "graceful slow teardown skips pkill" "pkill" "$LOG1"
assert_not_contains "graceful slow teardown never kills sddm-helper via loginctl" "loginctl" "$LOG1"
assert_eq "exit.sh preserves flock lock file" "yes" "$([ -e "$SB1/runtime/serpantinum/serpantinumd.lock" ] && echo yes || echo no)"
assert_eq "exit.sh preserves running daemon pid file" "yes" "$([ -e "$SB1/runtime/serpantinum/serpantinumd.pid" ] && echo yes || echo no)"

# Case 2: Hyprland hangs beyond timeout -> escalates to pkill start-hyprland / Hyprland -> loginctl last resort
SB2="$(setup_mock_env hung_wm 200)"
PATH="$SB2/bin:/usr/bin:/bin" \
XDG_RUNTIME_DIR="$SB2/runtime" \
DESKTOP_SESSION="hyprland" \
XDG_CURRENT_DESKTOP="Hyprland" \
HYPRLAND_INSTANCE_SIGNATURE="sig1" \
XDG_SESSION_ID="2" \
bash "$EXIT_SCRIPT" hyprland

LOG2="$(cat "$SB2/log")"
assert_contains "hung fallback signals wrapper before compositor" "pkill -SIGTERM" "$LOG2"
assert_contains "hung fallback reaches terminate_session last resort" "loginctl terminate-session 2" "$LOG2"

echo "Passed $PASS, Failed $FAIL"
[ "$FAIL" -eq 0 ]
