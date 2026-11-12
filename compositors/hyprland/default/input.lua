--  ▀  █▀▀▄ █▀▀█ █  █ ▀▀█▀▀
-- ▀█▀ █  █ █  █ █  █   █
-- ▀▀▀ ▀  ▀ █▀▀▀  ▀▀▀   ▀
-- See https://wiki.hyprland.org/Configuring/Variables/

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

hl.config({
    input = {
        kb_layout = "us,ru",
        kb_options = "grp:alt_shift_toggle,grp:ctrl_shift_toggle",
        numlock_by_default = true,
        follow_mouse = 1,
        sensitivity = 0,
        accel_profile = "flat",
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
            clickfinger_behavior = true,
        },
    },
})
