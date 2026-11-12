-- █▀▀█ █▀▀▄  ▀  █▀▄▀█ █▀▀█ ▀▀█▀▀  ▀  █▀▀█ █▀▀▄ █▀▀
-- █▄▄█ █  █ ▀█▀ █ ▀ █ █▄▄█   █   ▀█▀ █  █ █  █ ▀▀█
-- ▀  ▀ ▀  ▀ ▀▀▀ ▀   ▀ ▀  ▀   ▀   ▀▀▀ ▀▀▀▀ ▀  ▀ ▀▀▀
-- See https://wiki.hyprland.org/Configuring/Animations/

hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("winIn", { type = "bezier", points = { { 0.1, 1.1 }, { 0.1, 1.1 } } })
hl.curve("winOut", { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
hl.curve("liner", { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "wind", style = "slide" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "winIn", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "winOut", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "wind", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "liner" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "liner", style = "loop" })
hl.animation({ leaf = "fade", enabled = true, speed = 6, bezier = "wind" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "wind", style = "slide" })

hl.config({
    general = {
        border_size = 2,
        gaps_in = 4,
        gaps_out = 6,
        float_gaps = 6,
        resize_on_border = true,
        extend_border_grab_area = 30,
        "col.active_border = rgba(cba6f7ee) rgba(89b4faee) 45deg",
        "col.inactive_border = rgba(313244aa)",
    },
    decoration = {
        rounding = 12,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled = true,
            range = 15,
            render_power = 3,
            color = "rgba(00000055)",
        },
        blur = {
            enabled = true,
            size = 6,
            passes = 2,
            new_optimizations = true,
        },
    },
})
