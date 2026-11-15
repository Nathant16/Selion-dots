-- █ █ █ █ █▄ █ █▀▄ █▀█ █ █ █ 　 █▀█ █ █ █   █▀▀ █▀
-- ▀▄▀▄▀ █ █ ▀█ █▄▀ █▄█ ▀▄▀▄▀ 　 █▀▄ █▄█ █▄▄ ██▄ ▄█
-- See https://wiki.hyprland.org/Configuring/Window-Rules/

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

-- Dialogs & Tools
hl.window_rule({
    name = "float-tools",
    match = { class = "pavucontrol|pwvucontrol|blueman-manager|org.gnome.FileRoller|gnome-calculator|qalculate-gtk|org.gnome.Loupe|qt5ct|qt6ct|yad" },
    float = true,
    center = true,
})

-- Common File / Dialog Modals
hl.window_rule({
    name = "float-modals",
    match = { title = [=[^(Open|Open File|Choose Files|Save As|Confirm to replace files|File Operation Progress|File Upload.*|Authentication Required|Add Folder to Workspace|Choose wallpaper.*|Library.*|.*dialog.*)$]=] },
    float = true,
})

-- Picture-in-Picture
hl.window_rule({
    name = "picture_in_picture",
    match = { title = [=[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture|[Кк]артинка в картинке)(.*)$]=] },
    float = true,
    keep_aspect_ratio = true,
    move = { "(monitor_w*0.745)", "(monitor_h*0.74)" },
    size = { "(monitor_w*0.25)", "(monitor_h*0.25)" },
    pin = true,
})

-- Idle Inhibit for Media and Fullscreen Browsers
hl.window_rule({
    name = "idle-inhibit-media",
    match = { class = "^(.*celluloid.*)$|^(.*mpv.*)$|^(.*vlc.*)$" },
    idle_inhibit = "fullscreen",
})

hl.window_rule({
    name = "idle-inhibit-spotify",
    match = { class = "^(.*[Ss]potify.*)$" },
    idle_inhibit = "fullscreen",
})

hl.window_rule({
    name = "idle-inhibit-yandex-music",
    match = { class = "^(yandex-music)$" },
    idle_inhibit = "fullscreen",
})

hl.window_rule({
    name = "idle-inhibit-browsers",
    match = { class = "^(.*LibreWolf.*)$|^(.*floorp.*)$|^(.*brave-browser.*)$|^(.*firefox.*)$|^(.*chromium.*)$|^(.*zen.*)$|^(.*vivaldi.*)$" },
    idle_inhibit = "fullscreen",
})

-- Serpantinum dynamic window rules (opacity for kitty and ski)
pcall(function()
    local home = os.getenv("HOME") or ""
    local rules_file = home .. "/.local/state/serpantinum/theme_hyprland_rules.lua"
    local chunk = loadfile(rules_file)
    if chunk then chunk() end
end)
