function logout --description "Выход из графической сессии в SDDM"
    set -l exit_script "$HOME/.local/share/serpantinum/src/scripts/system/exit.sh"
    if test -f "$exit_script"
        bash "$exit_script"
        return
    end

    # Fallback to direct compositor detection and dispatch
    if test "$DESKTOP_SESSION" = "mango" -o "$XDG_CURRENT_DESKTOP" = "mango:wlroots"; or pgrep -x mango >/dev/null
        if test -z "$MANGO_INSTANCE_SIGNATURE"
            set -l sock (ls /run/user/(id -u)/mango-*.sock 2>/dev/null | head -n1)
            if test -n "$sock"
                set -gx MANGO_INSTANCE_SIGNATURE "$sock"
            end
        end
        mmsg dispatch quit 2>/dev/null; or pkill -SIGTERM -x mango 2>/dev/null; or loginctl terminate-session (loginctl session-status --no-legend 2>/dev/null | awk '{print $1; exit}') 2>/dev/null; or loginctl terminate-user $USER
    else if test "$DESKTOP_SESSION" = "umbriel" -o "$XDG_CURRENT_DESKTOP" = "Umbriel"; or pgrep -x umbriel >/dev/null
        umbriel msg session-quit skip-confirmation 2>/dev/null; or umbriel msg session-quit 2>/dev/null; or pkill -SIGTERM -x umbriel 2>/dev/null; or loginctl terminate-user $USER
    else if test "$DESKTOP_SESSION" = "driftwm" -o "$XDG_CURRENT_DESKTOP" = "driftwm:wlroots"; or pgrep -x driftwm >/dev/null
        driftwm msg action quit 2>/dev/null; or loginctl terminate-user $USER
    else if test "$DESKTOP_SESSION" = "niri" -o "$XDG_CURRENT_DESKTOP" = "niri"; or pgrep -x niri >/dev/null
        niri msg action quit --skip-confirmation 2>/dev/null; or loginctl terminate-user $USER
    else if test "$DESKTOP_SESSION" = "sway" -o "$XDG_CURRENT_DESKTOP" = "sway"; or pgrep -x sway >/dev/null
        swaymsg exit 2>/dev/null; or loginctl terminate-user $USER
    else if test "$DESKTOP_SESSION" = "hyprland" -o "$XDG_CURRENT_DESKTOP" = "Hyprland"; or pgrep -x Hyprland >/dev/null
        hyprctl dispatch exit 2>/dev/null; or hyprctl dispatch "hl.dsp.exit()" 2>/dev/null; or loginctl terminate-user $USER
    else
        loginctl terminate-user $USER
    end
end
