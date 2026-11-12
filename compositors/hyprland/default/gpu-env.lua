--  █▀▀█  █▀▀█  █  █ 　  █▀▀▄  █▀▀▀ ▀▀█▀▀  █▀▀▀  █▀▀█ ▀▀█▀▀
--  █ ▄▄  █▄▄█  █  █ 　  █  █  █▀▀▀   █    █▀▀▀  █      █
--  █▄▄█  █     ▀▄▄▀ 　  █▄▄▀  █▄▄▄   █    █▄▄▄  █▄▄█   █

-- GPU Auto-detection
local f = io.open(os.getenv("HOME") .. "/.config/hypr/gpu-env.lua", "r")
if f then
    f:close()
    require("gpu-env")
end
