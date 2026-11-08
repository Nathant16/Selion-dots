#!/usr/bin/env bash
TS="$1"
shift
RUN_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/serpantinum/screenshot"
mkdir -p "$RUN_DIR"

if [ $# -eq 0 ]; then
    grim "$RUN_DIR/lock_freeze_default_${TS}.png" 2>/dev/null || true
else
    for mon in "$@"; do
        grim -o "$mon" "$RUN_DIR/lock_freeze_${mon}_${TS}.png" 2>/dev/null || grim "$RUN_DIR/lock_freeze_${mon}_${TS}.png" 2>/dev/null || true
    done
    grim "$RUN_DIR/lock_freeze_default_${TS}.png" 2>/dev/null || true
fi
