--  █    █▀▀█ █  █ █▀▀▄ █▀▀ █  █
--  █    █▄▄█ █  █ █  █ █   █▀▀█
--  █▄▄█ ▀  ▀  ▀▀▀ ▀  ▀ ▀▀▀ ▀  ▀
-- See https://wiki.hyprland.org/Configuring/Keywords/

hl.on("hyprland.start", function()
    -- Clipboard manager
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Selion desktop shell & daemon
    hl.exec_cmd("serpantinumd start")
end)
