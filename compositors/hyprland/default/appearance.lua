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

local home = os.getenv("HOME") or ""
local theme_file = home .. "/.local/state/serpantinum/theme_hyprland.lua"
local active_1 = "rgba(cba6f7ee)"
local active_2 = "rgba(89b4faee)"
local inactive = "rgba(313244aa)"
local rounding = 12

local ok, theme = pcall(function()
    local chunk = loadfile(theme_file)
    if chunk then return chunk() end
    return nil
end)

if ok and type(theme) == "table" then
    if theme.active_border_1 then active_1 = theme.active_border_1 end
    if theme.active_border_2 then active_2 = theme.active_border_2 end
    if theme.inactive_border then inactive = theme.inactive_border end
    if theme.rounding then rounding = theme.rounding end
end

hl.config({
    general = {
        border_size = 2,
        gaps_in = 4,
        gaps_out = 6,
        float_gaps = 6,
        resize_on_border = true,
        extend_border_grab_area = 30,
        ["col.active_border"] = {
            colors = { active_1, active_2 },
            angle = 45,
        },
        ["col.inactive_border"] = inactive,
    },
    decoration = {
        rounding = rounding,
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
