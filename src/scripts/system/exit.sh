#!/usr/bin/env bash

UID_SELF="$(id -u)"

cleanup_user_session_env() {
    if command -v systemctl &>/dev/null; then
        systemctl --user unset-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE SWAYSOCK MANGO_INSTANCE_SIGNATURE UMBRIEL_SOCKET DRIFTWM_SOCKET 2>/dev/null || true
        systemctl --user stop --no-block graphical-session.target graphical-session-pre.target 2>/dev/null || true
    fi

    if command -v dinitctl &>/dev/null; then
        dinitctl --user stop graphical-session 2>/dev/null || true
    fi
}

is_proc_running() {
    pgrep -u "$UID_SELF" -x "$1" &>/dev/null
}

wait_proc_exit() {
    local proc="$1"
    local max_tenths="${2:-60}"
    local i=0
    while [ "$i" -lt "$max_tenths" ]; do
        if ! is_proc_running "$proc"; then
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

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
        *umbriel*)  TARGET="umbriel" ;;
    esac
fi

# Fallback: check which compositor process is actually running right now
if [ -z "$TARGET" ]; then
    if is_proc_running mango; then
        TARGET="mango"
    elif is_proc_running driftwm; then
        TARGET="driftwm"
    elif is_proc_running niri; then
        TARGET="niri"
    elif is_proc_running sway; then
        TARGET="sway"
    elif is_proc_running Hyprland; then
        TARGET="hyprland"
    elif is_proc_running umbriel; then
        TARGET="umbriel"
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

# Wait for graceful compositor teardown (and any parent watchdog like
# start-hyprland / niri-session) before signaling or calling loginctl. Killing
# sddm-helper via loginctl terminate-session makes SDDM log
# ERROR_INTERNAL ("Process crashed") and fail to respawn the greeter.
finish_wm_exit() {
    local proc="$1"
    local wrapper="${2:-}"

    cleanup_user_session_env

    if wait_proc_exit "$proc" 60; then
        [ -n "$wrapper" ] && wait_proc_exit "$wrapper" 20 || true
        return 0
    fi

    if [ -n "$wrapper" ] && is_proc_running "$wrapper"; then
        pkill -SIGTERM -u "$UID_SELF" -x "$wrapper" 2>/dev/null || true
        wait_proc_exit "$wrapper" 20 || true
    fi

    if is_proc_running "$proc"; then
        pkill -SIGTERM -u "$UID_SELF" -x "$proc" 2>/dev/null || true
        wait_proc_exit "$proc" 20 || true
    fi

    if is_proc_running "$proc" || { [ -n "$wrapper" ] && is_proc_running "$wrapper"; }; then
        terminate_session
    fi
}

quit_mango() {
    local rt="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"
    local sock="$MANGO_INSTANCE_SIGNATURE"
    if [ -z "$sock" ] || [ ! -S "$sock" ]; then
        sock="$(find "$rt" -maxdepth 1 -name "mango-*.sock" 2>/dev/null | head -n1)"
    fi
    if [ -n "$sock" ] && [ -S "$sock" ]; then
        export MANGO_INSTANCE_SIGNATURE="$sock"
    fi

    if command -v mmsg &>/dev/null && [ -n "$MANGO_INSTANCE_SIGNATURE" ]; then
        mmsg dispatch quit &>/dev/null || true
    fi

    finish_wm_exit "mango"
}

quit_driftwm() {
    driftwm msg action quit &>/dev/null || \
    driftwm msg quit &>/dev/null || true

    finish_wm_exit "driftwm"
}

quit_hyprland() {
    if command -v uwsm &>/dev/null && uwsm check is-active &>/dev/null; then
        uwsm stop &>/dev/null || true
    else
        local rt="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"
        if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ] || [ ! -S "$rt/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]; then
            local cand=""
            for cand in "$rt"/hypr/*/.socket.sock /tmp/hypr/*/.socket.sock; do
                [ -S "$cand" ] || continue
                HYPRLAND_INSTANCE_SIGNATURE="$(basename "$(dirname "$cand")")"
                export HYPRLAND_INSTANCE_SIGNATURE
                break
            done
        fi
        if command -v hyprshutdown &>/dev/null; then
            hyprshutdown &>/dev/null || \
            hyprctl dispatch 'hl.dsp.exit()' &>/dev/null || \
            hyprctl dispatch exit &>/dev/null || true
        else
            hyprctl dispatch 'hl.dsp.exit()' &>/dev/null || \
            hyprctl dispatch exit &>/dev/null || true
        fi
    fi

    finish_wm_exit "Hyprland" "start-hyprland"
}

quit_niri() {
    local rt="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"
    if [ -z "$NIRI_SOCKET" ] || [ ! -S "$NIRI_SOCKET" ]; then
        NIRI_SOCKET="$(ls "$rt"/niri.*.sock 2>/dev/null | head -n1)"
        export NIRI_SOCKET
    fi
    niri msg action quit --skip-confirmation &>/dev/null || \
    niri msg action quit &>/dev/null || true

    finish_wm_exit "niri" "niri-session"
}

quit_umbriel() {
    umbriel msg session-quit skip-confirmation &>/dev/null || \
    umbriel msg session-quit &>/dev/null || true

    finish_wm_exit "umbriel"
}

quit_sway() {
    local rt="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"
    if [ -z "$SWAYSOCK" ] || [ ! -S "$SWAYSOCK" ]; then
        SWAYSOCK="$(ls "$rt"/sway-ipc.*.sock 2>/dev/null | head -n1)"
        export SWAYSOCK
    fi
    swaymsg exit &>/dev/null || true

    finish_wm_exit "sway"
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
    umbriel)
        quit_umbriel
        ;;
    sway)
        quit_sway
        ;;
    *)
        if is_proc_running mango; then
            quit_mango
        elif is_proc_running driftwm; then
            quit_driftwm
        elif is_proc_running niri; then
            quit_niri
        elif is_proc_running sway; then
            quit_sway
        elif is_proc_running Hyprland; then
            quit_hyprland
        elif is_proc_running umbriel; then
            quit_umbriel
        else
            cleanup_user_session_env
            terminate_session
        fi
        ;;
esac
