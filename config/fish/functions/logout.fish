function logout --description "Выход из графической сессии в SDDM"
    if set -q HYPRLAND_INSTANCE_SIGNATURE
        hyprctl dispatch exit 2>/dev/null; or hyprctl dispatch "hl.dsp.exit()" 2>/dev/null; or loginctl terminate-user $USER
    else if set -q SWAYSOCK; or pgrep -x sway >/dev/null
        swaymsg exit 2>/dev/null; or loginctl terminate-user $USER
    else if set -q DRIFTWM_SOCKET; or pgrep -x driftwm >/dev/null
        driftwm msg action quit 2>/dev/null; or loginctl terminate-user $USER
    else if set -q NIRI_SOCKET; or pgrep -x niri >/dev/null
        niri msg action quit --skip-confirmation 2>/dev/null; or loginctl terminate-user $USER
    else if set -q MANGO_INSTANCE_SIGNATURE; or pgrep -x mango >/dev/null
        mmsg dispatch quit 2>/dev/null; or pkill -SIGTERM -x mango 2>/dev/null; or loginctl terminate-user $USER
    else
        loginctl terminate-user $USER
    end
end
