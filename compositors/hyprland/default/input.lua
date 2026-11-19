--  ▀  █▀▀▄ █▀▀█ █  █ ▀▀█▀▀
-- ▀█▀ █  █ █  █ █  █   █
-- ▀▀▀ ▀  ▀ █▀▀▀  ▀▀▀   ▀
-- See https://wiki.hyprland.org/Configuring/Variables/

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

hl.gesture({
    fingers = 3,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.exec_cmd("serpantinum msg toggle launcher"))
    end,
})

hl.config({
    input = {
        kb_layout = "us,ru",
        -- Only one grp:*_toggle may own LFSH: combining alt_shift and
        -- ctrl_shift makes ctrl win and breaks the Alt-then-Shift order.
        kb_options = "grp:alt_shift_toggle",
        numlock_by_default = true,
        follow_mouse = 1,
        sensitivity = 0,
        accel_profile = "flat",
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
            clickfinger_behavior = true,
            disable_while_typing = true,
        },
    },
})
