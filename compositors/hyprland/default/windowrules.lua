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
