#!/usr/bin/env bash

ACTION="${1:-close}"

# Detect internal laptop monitor (typically eDP-1)
INTERNAL_MONITOR=""
for mon in /sys/class/drm/*/status; do
    if [[ "$mon" == *"eDP"* ]]; then
        INTERNAL_MONITOR="$(basename "$(dirname "$mon")" | sed 's/^card[0-9]*-//')"
        break
    fi
done
[ -n "$INTERNAL_MONITOR" ] || INTERNAL_MONITOR="eDP-1"

# Check if ANY external monitor is connected
has_external=false
for mon in /sys/class/drm/*/status; do
    [ -f "$mon" ] || continue
    if [[ "$mon" != *"eDP"* ]] && grep -q "^connected" "$mon" 2>/dev/null; then
        has_external=true
        break
    fi
done

# Resolve Hyprland instance signature if not set
if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ -d "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" ]; then
    local_hs=$(ls -d "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"/* 2>/dev/null | head -n 1)
    [ -n "$local_hs" ] && export HYPRLAND_INSTANCE_SIGNATURE="$(basename "$local_hs")"
fi

case "$ACTION" in
    close)
        if [ "$has_external" = true ]; then
            # Clamshell mode: keep laptop running on external display, disable internal screen
            if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
                hyprctl keyword monitor "$INTERNAL_MONITOR, disable" >/dev/null 2>&1 || true
            elif [ -n "$SWAYSOCK" ]; then
                swaymsg output "$INTERNAL_MONITOR" disable >/dev/null 2>&1 || true
            elif [ -n "$NIRI_SOCKET" ]; then
                niri msg action output "$INTERNAL_MONITOR" off >/dev/null 2>&1 || true
            fi
        else
            # Standalone mode: lock screen and suspend
            serpantinum lock >/dev/null 2>&1 || true
            systemctl suspend >/dev/null 2>&1 || true
        fi
        ;;
    open)
        # Re-enable internal laptop screen
        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
            hyprctl keyword monitor "$INTERNAL_MONITOR, preferred, auto, 1" >/dev/null 2>&1 || true
        elif [ -n "$SWAYSOCK" ]; then
            swaymsg output "$INTERNAL_MONITOR" enable >/dev/null 2>&1 || true
        elif [ -n "$NIRI_SOCKET" ]; then
            niri msg action output "$INTERNAL_MONITOR" on >/dev/null 2>&1 || true
        fi
        ;;
    status)
        echo "Internal Monitor: $INTERNAL_MONITOR"
        echo "External Connected: $has_external"
        ;;
    *)
        echo "Usage: serpantinum clamshell [close|open|status]" >&2
        exit 1
        ;;
esac
