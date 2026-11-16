#!/usr/bin/env bash

rm -f /tmp/serpantinumd.lock /tmp/serpantinumd.pid 2>/dev/null

if command -v systemctl &>/dev/null; then
    systemctl --user stop graphical-session.target 2>/dev/null
    systemctl --user stop graphical-session-pre.target 2>/dev/null
fi

if command -v dinitctl &>/dev/null; then
    dinitctl --user stop graphical-session 2>/dev/null
fi

sleep 0.2

TARGET="${1:-}"

# Resolve target compositor from environment if not passed explicitly
if [ -z "$TARGET" ]; then
    session_str="${DESKTOP_SESSION,,} ${XDG_CURRENT_DESKTOP,,} ${XDG_SESSION_DESKTOP,,}"
    case "$session_str" in
        *mango*)    TARGET="mango" ;;
        *drift*)    TARGET="driftwm" ;;
        *hyprland*) TARGET="hyprland" ;;
        *niri*)     TARGET="niri" ;;
        *sway*)     TARGET="sway" ;;
    esac
fi

# Fallback: check which compositor process is actually running right now
if [ -z "$TARGET" ]; then
    if pgrep -x mango &>/dev/null; then
        TARGET="mango"
    elif pgrep -x driftwm &>/dev/null; then
        TARGET="driftwm"
    elif pgrep -x niri &>/dev/null; then
        TARGET="niri"
    elif pgrep -x sway &>/dev/null; then
        TARGET="sway"
    elif pgrep -x Hyprland &>/dev/null; then
        TARGET="hyprland"
    fi
fi

terminate_session() {
    if command -v loginctl &>/dev/null; then
        local sid="${XDG_SESSION_ID:-}"
        if [ -n "$sid" ] && [ "$sid" != "self" ]; then
            loginctl terminate-session "$sid" 2>/dev/null && return 0
        fi
        loginctl terminate-session "${XDG_SESSION_ID:-self}" 2>/dev/null || \
        loginctl terminate-user "$USER" 2>/dev/null || true
    fi
}

quit_mango() {
    local uid="$(id -u)"
    local sock="$MANGO_INSTANCE_SIGNATURE"
    if [ -z "$sock" ] || [ ! -S "$sock" ]; then
        sock="$(find "/run/user/$uid" -maxdepth 1 -name "mango-*.sock" 2>/dev/null | head -n1)"
    fi
    if [ -n "$sock" ] && [ -S "$sock" ]; then
        export MANGO_INSTANCE_SIGNATURE="$sock"
    fi

    if command -v mmsg &>/dev/null && [ -n "$MANGO_INSTANCE_SIGNATURE" ]; then
        mmsg dispatch quit 2>/dev/null
    fi

    sleep 0.2
    if ! pgrep -x mango &>/dev/null; then
        return 0
    fi

    pkill -SIGTERM -x mango 2>/dev/null
    sleep 0.2
    if ! pgrep -x mango &>/dev/null; then
        return 0
    fi

    terminate_session
}

quit_driftwm() {
    driftwm msg action quit 2>/dev/null || \
    driftwm msg quit 2>/dev/null || \
    pkill -SIGTERM -x driftwm 2>/dev/null

    sleep 0.2
    if pgrep -x driftwm &>/dev/null; then
        terminate_session
    fi
}

quit_hyprland() {
    local uid="$(id -u)"
    if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        HYPRLAND_INSTANCE_SIGNATURE=$(ls -1 "/run/user/$uid/hypr/" 2>/dev/null | head -n1 || ls -1 /tmp/hypr/ 2>/dev/null | head -n1)
        export HYPRLAND_INSTANCE_SIGNATURE
    fi
    hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || \
    hyprctl dispatch exit 2>/dev/null || \
    pkill -SIGTERM -x Hyprland 2>/dev/null

    sleep 0.2
    if pgrep -x Hyprland &>/dev/null; then
        terminate_session
    fi
}

quit_niri() {
    local uid="$(id -u)"
    if [ -z "$NIRI_SOCKET" ]; then
        NIRI_SOCKET=$(ls "/run/user/$uid"/niri.*.sock 2>/dev/null | head -n1)
        export NIRI_SOCKET
    fi
    niri msg action quit --skip-confirmation 2>/dev/null || \
    niri msg action quit 2>/dev/null || \
    pkill -SIGTERM -x niri 2>/dev/null

    sleep 0.2
    if pgrep -x niri &>/dev/null; then
        terminate_session
    fi
}

quit_sway() {
    swaymsg exit 2>/dev/null || \
    pkill -SIGTERM -x sway 2>/dev/null

    sleep 0.2
    if pgrep -x sway &>/dev/null; then
        terminate_session
    fi
}

case "$TARGET" in
    mango)
        quit_mango
        ;;
    driftwm)
        quit_driftwm
        ;;
    hyprland)
        quit_hyprland
        ;;
    niri)
        quit_niri
        ;;
    sway)
        quit_sway
        ;;
    *)
        if pgrep -x mango &>/dev/null; then
            quit_mango
        elif pgrep -x driftwm &>/dev/null; then
            quit_driftwm
        elif pgrep -x niri &>/dev/null; then
            quit_niri
        elif pgrep -x sway &>/dev/null; then
            quit_sway
        elif pgrep -x Hyprland &>/dev/null; then
            quit_hyprland
        else
            terminate_session
        fi
        ;;
esac
