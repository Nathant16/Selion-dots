-- ██████╗  █████╗   ███╗  ██╗ █████╗ ████████╗  ███████╗██████╗ ██╗████████╗
-- ██╔══██╗██╔══██╗  ████╗ ██║██╔══██╗╚══██╔══╝  ██╔════╝██╔══██╗██║╚══██╔══╝
-- ██║  ██║██║  ██║  ██╔██╗██║██║  ██║   ██║     █████╗  ██║  ██║██║   ██║
-- ██║  ██║██║  ██║  ██║╚████║██║  ██║   ██║     ██╔══╝  ██║  ██║██║   ██║
-- ██████╔╝╚█████╔╝  ██║ ╚███║╚█████╔╝   ██║     ███████╗██████╔╝██║   ██║
-- ╚═════╝  ╚════╝   ╚═╝  ╚══╝ ╚════╝    ╚═╝     ╚══════╝╚═════╝ ╚═╝   ╚═╝


-- █▀▀ █▀▀▄ ▀█ █▀  ▀  █▀▀█ █▀▀█ █▀▀▄ █▀▄▀█ █▀▀ █▀▀▄ ▀▀█▀▀
-- █▀▀ █  █  █▄█  ▀█▀ █▄▄▀ █  █ █  █ █ ▀ █ █▀▀ █  █   █
-- ▀▀▀ ▀  ▀   ▀   ▀▀▀ ▀ ▀▀ ▀▀▀▀ ▀  ▀ ▀   ▀ ▀▀▀ ▀  ▀   ▀
-- See https://wiki.hyprland.org/Configuring/Environment-variables/

-- Hyprland
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Environment
hl.on("hyprland.start", function()
    hl.exec_cmd([[sh -c 'if [ -x /usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator ]; then set -a; eval "$(/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator)"; set +a; fi; dbus-update-activation-environment --systemd --all']])
end)

-- GPU env
require("default/gpu-env")


-- █▀▀ █▀▀█ █  █ █▀▀█ █▀▀ █▀▀
-- ▀▀█ █  █ █  █ █▄▄▀ █   █▀▀
-- ▀▀▀ ▀▀▀▀  ▀▀▀ ▀ ▀▀ ▀▀▀ ▀▀▀

require("default/autostart")
require("default/monitors")
require("default/input")
require("default/keybindings")
require("default/windowrules")
require("default/appearance")
require("default/general")
pcall(require, "userprefs")
