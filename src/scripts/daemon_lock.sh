#!/usr/bin/env bash
# Shared single-instance lock, PID tracking, and scoped process discovery for serpantinum/serpantinumd.

declare -F daemon_runtime_dir >/dev/null 2>&1 && return 0

DAEMON_UID="$(id -u)"

daemon_runtime_dir() {
    local dir
    if [ -n "${SERPANTINUM_RUNTIME_DIR:-}" ]; then
        dir="$SERPANTINUM_RUNTIME_DIR"
    elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -w "${XDG_RUNTIME_DIR:-}" ]; then
        dir="${XDG_RUNTIME_DIR%/}/serpantinum"
    else
        dir="/tmp/serpantinum-$DAEMON_UID"
    fi
    mkdir -p "$dir" 2>/dev/null || true
    printf '%s\n' "$dir"
}

daemon_init_paths() {
    DAEMON_RUNTIME_DIR="$(daemon_runtime_dir)"
    DAEMON_LOCK_FILE="$DAEMON_RUNTIME_DIR/serpantinumd.lock"
    DAEMON_PID_FILE="$DAEMON_RUNTIME_DIR/serpantinumd.pid"
    LEGACY_DAEMON_PID_FILE="/tmp/serpantinumd.pid"
    export DAEMON_RUNTIME_DIR DAEMON_LOCK_FILE DAEMON_PID_FILE LEGACY_DAEMON_PID_FILE
}

daemon_is_alive() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    local stat
    stat=$(<"/proc/$pid/stat") 2>/dev/null || return 1
    [[ "$stat" =~ \)\ Z ]] && return 1
    return 0
}

daemon_terminate_and_wait() {
    local pid="$1"
    local timeout="${2:-2}"
    local count=0
    local max_count=$(( timeout * 20 ))

    if [ -z "$pid" ] || ! daemon_is_alive "$pid"; then
        return 0
    fi

    kill -TERM "$pid" 2>/dev/null || true

    while daemon_is_alive "$pid"; do
        if [ "$count" -ge "$max_count" ]; then
            kill -KILL "$pid" 2>/dev/null || true
            break
        fi
        sleep 0.05
        count=$((count + 1))
    done
}

# Parse target process environment once using bash builtins for zero subshell overhead.
daemon_proc_info() {
    local pid="$1"
    _DP_HOME=""
    _DP_XDG_RUNTIME=""
    _DP_SERP_RUNTIME=""
    _DP_WAYLAND=""
    [ -r "/proc/$pid/environ" ] || return 1
    local entry k v
    while IFS= read -r -d '' entry || [ -n "$entry" ]; do
        k="${entry%%=*}"
        v="${entry#*=}"
        case "$k" in
            HOME) _DP_HOME="$v" ;;
            XDG_RUNTIME_DIR) _DP_XDG_RUNTIME="$v" ;;
            SERPANTINUM_RUNTIME_DIR) _DP_SERP_RUNTIME="$v" ;;
            WAYLAND_DISPLAY) _DP_WAYLAND="$v" ;;
        esac
    done < "/proc/$pid/environ" 2>/dev/null || return 1
    return 0
}

daemon_proc_matches_scope() {
    local pid="$1"
    daemon_proc_info "$pid" || return 1
    if [ -n "${SERPANTINUM_RUNTIME_DIR:-}" ] || [ -n "$_DP_SERP_RUNTIME" ]; then
        [ "$_DP_SERP_RUNTIME" = "${SERPANTINUM_RUNTIME_DIR:-}" ] || return 1
    else
        [ "$_DP_HOME" = "${HOME:-}" ] || return 1
        [ "$_DP_XDG_RUNTIME" = "${XDG_RUNTIME_DIR:-}" ] || return 1
    fi
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "$_DP_WAYLAND" ] && [ "$_DP_WAYLAND" != "$WAYLAND_DISPLAY" ]; then
        return 1
    fi
    return 0
}

daemon_session_matches_display() {
    local pid="$1"
    daemon_proc_info "$pid" || return 0
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "$_DP_WAYLAND" ] && [ "$_DP_WAYLAND" != "$WAYLAND_DISPLAY" ]; then
        return 1
    fi
    if [ -n "$_DP_WAYLAND" ]; then
        local rdir="${_DP_XDG_RUNTIME:-/run/user/$DAEMON_UID}"
        local sock="$rdir/$_DP_WAYLAND"
        # Only treat missing socket as dead compositor when sockets exist in runtime dir (skip in headless mocks).
        if [ ! -e "$sock" ] && { [ -z "${SERPANTINUM_RUNTIME_DIR:-}" ] || { [ -n "${WAYLAND_DISPLAY:-}" ] && [ -e "${XDG_RUNTIME_DIR:-$rdir}/$WAYLAND_DISPLAY" ]; }; }; then
            return 1
        fi
    fi
    return 0
}

daemon_find_scoped_processes() {
    local mode="$1" # daemon | quickshell | screentime | all
    local cmd_file pid a0 a1 arg has_p has_ipc qml_arg saw_action action_ok is_match
    local -a args

    for cmd_file in /proc/[0-9]*/cmdline; do
        pid="${cmd_file#/proc/}"
        pid="${pid%/cmdline}"
        [[ "$pid" == "$$" || "$pid" == "$PPID" ]] && continue
        [ -O "$cmd_file" ] || continue

        args=()
        while IFS= read -r -d '' arg || [ -n "$arg" ]; do
            args+=("$arg")
        done < "$cmd_file" 2>/dev/null
        [ "${#args[@]}" -gt 0 ] || continue

        a0="${args[0]##*/}"
        a1="${args[1]:-}"
        a1="${a1##*/}"
        is_match=false

        if [[ "$mode" == "daemon" || "$mode" == "all" ]]; then
            local idx_start=""
            if [[ "$a0" == "serpantinumd" || "$a0" == ".serpantinumd-wrapped" ]]; then
                idx_start=1
            elif [[ ( "$a0" == "bash" || "$a0" == "sh" ) && ( "$a1" == "serpantinumd" || "$a1" == ".serpantinumd-wrapped" ) ]]; then
                idx_start=2
            fi
            if [ -n "$idx_start" ]; then
                saw_action=""
                action_ok=true
                local i
                for (( i=idx_start; i<${#args[@]}; i++ )); do
                    case "${args[$i]}" in
                        -v|--verbose) ;;
                        start) saw_action="start" ;;
                        stop|restart|status|-h|--help|-V|--version)
                            action_ok=false
                            break
                            ;;
                        *) ;;
                    esac
                done
                if [ "$action_ok" = true ] && { [ -z "$saw_action" ] || [ "$saw_action" = "start" ]; }; then
                    is_match=true
                fi
            fi
        fi

        if [ "$is_match" = false ] && [[ "$mode" == "quickshell" || "$mode" == "all" ]]; then
            local qs_idx_start=""
            if [[ "$a0" == "quickshell" || "$a0" == ".quickshell-wrapped" ]]; then
                qs_idx_start=1
            elif [[ ( "$a0" == "bash" || "$a0" == "sh" ) && ( "$a1" == "quickshell" || "$a1" == ".quickshell-wrapped" ) ]]; then
                qs_idx_start=2
            fi
            if [ -n "$qs_idx_start" ]; then
                has_p=false
                has_ipc=false
                qml_arg=""
                local i
                for (( i=qs_idx_start; i<${#args[@]}; i++ )); do
                    if [ "${args[$i]}" = "-p" ] && [ $((i + 1)) -lt "${#args[@]}" ]; then
                        has_p=true
                        qml_arg="${args[$((i + 1))]}"
                    elif [ "${args[$i]}" = "ipc" ]; then
                        has_ipc=true
                    fi
                done
                if [ "$has_p" = true ] && [ "$has_ipc" = false ]; then
                    if { [ -n "${MAIN_QML:-}" ] && [ "$qml_arg" = "$MAIN_QML" ]; } || [[ "$qml_arg" == */quickshell/Shell.qml || "$qml_arg" == */Shell.qml || "$qml_arg" == */Bar.qml ]]; then
                        is_match=true
                    fi
                fi
            fi
        fi

        if [ "$is_match" = false ] && [[ "$mode" == "screentime" || "$mode" == "all" ]]; then
            if [[ "$a0" == "serpantinum-core" && "${args[1]:-}" == "screentime" && "${args[2]:-}" == "track" ]]; then
                is_match=true
            fi
        fi

        if [ "$is_match" = true ] && daemon_proc_matches_scope "$pid"; then
            printf '%s\n' "$pid"
        fi
    done
}

daemon_kill_matching_group() {
    local mode="$1"
    local sig="${2:-TERM}"
    local pids p
    pids="$(daemon_find_scoped_processes "$mode")"
    [ -n "$pids" ] || return 0
    for p in $pids; do
        kill "-$sig" "$p" 2>/dev/null || true
    done
    if [ "$sig" = "TERM" ]; then
        local c=0
        while [ "$c" -lt 40 ]; do
            local alive=false
            for p in $pids; do
                if daemon_is_alive "$p"; then
                    alive=true
                    break
                fi
            done
            [ "$alive" = false ] && break
            sleep 0.05
            c=$((c + 1))
        done
    fi
}

daemon_cleanup_stray_duplicates() {
    if [ -z "${SERPANTINUM_RUNTIME_DIR:-}" ] && [ -f "$LEGACY_DAEMON_PID_FILE" ]; then
        local lpid=""
        read -r lpid < "$LEGACY_DAEMON_PID_FILE" 2>/dev/null
        if [ -n "$lpid" ] && [ "$lpid" != "$$" ] && daemon_is_alive "$lpid" && daemon_proc_matches_scope "$lpid"; then
            daemon_terminate_and_wait "$lpid" 2
        fi
        rm -f "$LEGACY_DAEMON_PID_FILE" 2>/dev/null || true
    fi

    daemon_kill_matching_group daemon TERM
    daemon_kill_matching_group daemon KILL
    daemon_kill_matching_group quickshell TERM
    daemon_kill_matching_group quickshell KILL
}

daemon_stop_scoped() {
    local pid=""
    [ -f "$DAEMON_PID_FILE" ] && read -r pid < "$DAEMON_PID_FILE" 2>/dev/null
    if [ -n "$pid" ] && daemon_is_alive "$pid" && daemon_proc_matches_scope "$pid"; then
        daemon_terminate_and_wait "$pid" 3
    fi

    if [ -z "${SERPANTINUM_RUNTIME_DIR:-}" ] && [ -f "$LEGACY_DAEMON_PID_FILE" ]; then
        local lpid=""
        read -r lpid < "$LEGACY_DAEMON_PID_FILE" 2>/dev/null
        if [ -n "$lpid" ] && daemon_is_alive "$lpid" && daemon_proc_matches_scope "$lpid"; then
            daemon_terminate_and_wait "$lpid" 3
        fi
        rm -f "$LEGACY_DAEMON_PID_FILE" 2>/dev/null || true
    fi

    daemon_kill_matching_group daemon TERM
    daemon_kill_matching_group daemon KILL
    daemon_kill_matching_group quickshell TERM
    daemon_kill_matching_group quickshell KILL
    daemon_kill_matching_group screentime TERM
    daemon_kill_matching_group screentime KILL

    rm -f "$DAEMON_PID_FILE" 2>/dev/null || true
    # Intentionally preserve $DAEMON_LOCK_FILE so flock stays bound to a single inode.
}
