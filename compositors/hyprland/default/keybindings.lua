-- █ █ █▀▀ █  █ █▀▀▄  ▀  █▀▀▄ █▀▀▄  ▀  █▀▀▄ █▀▀▀ █▀▀
-- █▀▄ █▀▀ █▄▄█ █▀▀▄ ▀█▀ █  █ █  █ ▀█▀ █  █ █ ▀█ ▀▀█
-- ▀ ▀ ▀▀▀ ▄▄▄█ ▀▀▀  ▀▀▀ ▀  ▀ ▀▀▀  ▀▀▀ ▀  ▀ ▀▀▀▀ ▀▀▀

local mainMod = "SUPER"
local subMod = mainMod .. " + SHIFT"
local terminal = "kitty"

-- ==> Mouse Bindings
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ==> Terminal, File Manager & Task Manager
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal), { description = "Open terminal" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("ski"), { description = "Open file manager" })
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd(terminal .. " -e btop"), { description = "Open system monitor" })

-- ==> App Launchers (Synchronized with userprefs)
hl.bind(subMod .. " + C", hl.dsp.exec_cmd("code"), { description = "Open Visual Studio Code" })
hl.bind(subMod .. " + F", hl.dsp.exec_cmd("zen-browser"), { description = "Open Zen Browser" })
hl.bind(subMod .. " + A", hl.dsp.exec_cmd("antigravity-ide"), { description = "Open Antigravity IDE" })
hl.bind(subMod .. " + S", hl.dsp.exec_cmd("spotify"), { description = "Open Spotify" })
hl.bind(subMod .. " + T", hl.dsp.exec_cmd("AyuGram"), { description = "Open AyuGram" })
hl.bind(subMod .. " + G", hl.dsp.exec_cmd("steam"), { description = "Open Steam" })
hl.bind(subMod .. " + M", hl.dsp.exec_cmd("prismlauncher"), { description = "Open Prism Launcher" })
hl.bind(subMod .. " + D", hl.dsp.exec_cmd("discord"), { description = "Open Discord" })
hl.bind(subMod .. " + O", hl.dsp.exec_cmd("obsidian"), { description = "Open Obsidian" })
hl.bind(subMod .. " + P", hl.dsp.exec_cmd("pwvucontrol"), { description = "Open audio control" })

-- ==> Shell, Launcher, Clipboard & System
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("serpantinum msg toggle launcher"), { description = "Toggle application launcher" })
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("serpantinum msg toggle launcher"), { description = "Toggle application launcher" })
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("serpantinum msg toggle clipboard"), { description = "Toggle clipboard manager" })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("/usr/local/bin/battery --cycle"), { description = "Cycle power profile" })
hl.bind("XF86Launch1", hl.dsp.exec_cmd("/usr/local/bin/battery --cycle"), { description = "Cycle power profile" })

hl.bind(subMod .. " + X", hl.dsp.exec_cmd("serpantinum lock"), { description = "Lock screen / Power menu" })
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("serpantinum lock"), { description = "Lock screen / Power menu" })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("serpantinum lock"), { locked = true, description = "Lock screen" })
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("serpantinum lock"), { locked = true, description = "Lock screen" })

hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("serpantinum msg bar autohide"), { description = "Toggle status bar / shell" })
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("serpantinum msg toggle wallpaper"), { description = "Toggle wallpaper picker" })

-- ==> Window Actions
hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { description = "Close window" })
hl.bind(mainMod .. " + K", hl.dsp.window.kill(), { description = "Kill window" })
hl.bind("ALT + Return", hl.dsp.window.fullscreen(), { description = "Toggle fullscreen" })
hl.bind(subMod .. " + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), { description = "Toggle maximized" })

-- ==> Focus / Navigation
hl.bind(mainMod .. " + Left", hl.dsp.focus({ direction = "left" }), { description = "Focus window left" })
hl.bind(mainMod .. " + Right", hl.dsp.focus({ direction = "right" }), { description = "Focus window right" })
hl.bind(mainMod .. " + Up", hl.dsp.focus({ direction = "up" }), { description = "Focus window up" })
hl.bind(mainMod .. " + Down", hl.dsp.focus({ direction = "down" }), { description = "Focus window down" })
hl.bind("ALT + Tab", hl.dsp.focus({ direction = "down" }), { description = "Switch to next window" })

-- ==> Resize Windows
hl.bind(subMod .. " + Left", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true, description = "Resize window left" })
hl.bind(subMod .. " + Right", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true, description = "Resize window right" })
hl.bind(subMod .. " + Up", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true, description = "Resize window up" })
hl.bind(subMod .. " + Down", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true, description = "Resize window down" })

-- ==> Move Windows
hl.bind(mainMod .. " + SHIFT + CTRL + Left", hl.dsp.window.move({ direction = "l" }), { description = "Move window left" })
hl.bind(mainMod .. " + SHIFT + CTRL + Right", hl.dsp.window.move({ direction = "r" }), { description = "Move window right" })
hl.bind(mainMod .. " + SHIFT + CTRL + Up", hl.dsp.window.move({ direction = "u" }), { description = "Move window up" })
hl.bind(mainMod .. " + SHIFT + CTRL + Down", hl.dsp.window.move({ direction = "d" }), { description = "Move window down" })
hl.bind(mainMod .. " + CTRL + Left", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + CTRL + Right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + CTRL + Up", hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + CTRL + Down", hl.dsp.window.move({ direction = "d" }))

-- ==> Special Workspace
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special(), { description = "Show special workspace" })
hl.bind(mainMod .. " + ALT + S", hl.dsp.window.move({ workspace = "special" }), { description = "Move window to special workspace" })

-- ==> Workspaces 1..10
for i = 1, 10 do
  local ws = tostring(i)
  local key = tostring(i % 10)
  hl.bind(mainMod .. " + " .. key, hl.dsp.exec_cmd("serpantinum msg workspace " .. ws), { description = "Switch to workspace " .. ws })
  hl.bind(subMod .. " + " .. key, hl.dsp.exec_cmd("serpantinum msg workspace " .. ws .. " move"), { description = "Move window to workspace " .. ws })
end

hl.bind(mainMod .. " + CTRL + Right", hl.dsp.focus({ workspace = "r+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + CTRL + Left", hl.dsp.focus({ workspace = "r-1" }), { description = "Previous workspace" })
hl.bind(mainMod .. " + CTRL + Down", hl.dsp.focus({ workspace = "empty" }), { description = "First empty workspace" })
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Scroll workspaces forward" })
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { description = "Scroll workspaces back" })

-- ==> Screenshots
hl.bind("Print", hl.dsp.exec_cmd("serpantinum screenshot"), { locked = true, description = "Screenshot GUI" })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("serpantinum screenshot --edit"), { locked = true, description = "Screenshot and edit" })
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("serpantinum screenshot --full"), { locked = true, description = "Fullscreen screenshot" })
hl.bind(subMod .. " + Print", hl.dsp.exec_cmd("serpantinum screenshot --full --edit"), { locked = true, description = "Fullscreen screenshot and edit" })

-- ==> Hardware & Multimedia Controls
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("serpantinum brightness lower"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("serpantinum brightness raise"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("serpantinum volume lower"), { repeating = true, locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("serpantinum volume raise"), { repeating = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("serpantinum volume mute-toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("serpantinum volume mic-toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
