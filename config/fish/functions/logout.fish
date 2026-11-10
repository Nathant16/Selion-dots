function logout --description "Выход из графической сессии в SDDM"
    if set -q HYPRLAND_INSTANCE_SIGNATURE
        hyprctl dispatch exit 2>/dev/null; or hyprctl dispatch "hl.dsp.exit()" 2>/dev/null; or loginctl terminate-user $USER
    else if set -q SWAYSOCK; or pgrep -x sway >/dev/null
        swaymsg exit 2>/dev/null; or loginctl terminate-user $USER
    else if command -v driftwm >/dev/null; and test -n "$DRIFTWM_SOCKET"
        driftwm msg action quit 2>/dev/null; or loginctl terminate-user $USER
    else
        loginctl terminate-user $USER
    end
end
