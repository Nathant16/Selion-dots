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

hl.window_rule({
    name = "float-dialogs",
    match = { class = "pavucontrol|pwvucontrol|org.gnome.FileRoller|blueman-manager" },
    float = true,
})

hl.window_rule({
    name = "picture-in-picture",
    match = { title = "Picture-in-Picture|Picture in picture" },
    float = true,
    pin = true,
})

-- Serpantinum dynamic window rules (opacity for kitty and ski)
pcall(function()
    local home = os.getenv("HOME") or ""
    local rules_file = home .. "/.local/state/serpantinum/theme_hyprland_rules.lua"
    local chunk = loadfile(rules_file)
    if chunk then chunk() end
end)
