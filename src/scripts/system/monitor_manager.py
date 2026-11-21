#!/usr/bin/env python3
"""
Serpantinum Unified Monitor Manager
Applies and persists display resolution, refresh rate, and scaling
across supported Wayland compositors:
- driftwm (~/.config/driftwm/config.toml)
- hyprland (~/.config/hypr/default/monitors.lua)
- sway (~/.config/sway/default/monitors)
- niri (~/.config/niri/default/monitors.kdl)
- mango (~/.config/mango/default/monitors.conf)
- umbriel (~/.config/umbriel via umbriel config set)
- generic wlroots (wlr-randr)
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
from pathlib import Path

def get_wayland_env():
    env = dict(os.environ)
    if not env.get("XDG_RUNTIME_DIR"):
        uid = os.getuid()
        env["XDG_RUNTIME_DIR"] = f"/run/user/{uid}"
    runtime_dir = env["XDG_RUNTIME_DIR"]

    if not env.get("WAYLAND_DISPLAY") and os.path.exists(runtime_dir):
        for sock in sorted(glob.glob(f"{runtime_dir}/wayland-*")):
            if not sock.endswith(".lock"):
                env["WAYLAND_DISPLAY"] = os.path.basename(sock)
                break

    if not env.get("HYPRLAND_INSTANCE_SIGNATURE") and os.path.exists(f"{runtime_dir}/hypr"):
        socks = glob.glob(f"{runtime_dir}/hypr/*/.socket.sock")
        if socks:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = os.path.basename(os.path.dirname(socks[0]))

    if not env.get("SWAYSOCK"):
        sw_socks = glob.glob(f"{runtime_dir}/sway-ipc.*.sock")
        if sw_socks:
            env["SWAYSOCK"] = sw_socks[0]

    return env

def detect_compositor(env):
    # 1. Environment variables
    desktop = (env.get("XDG_CURRENT_DESKTOP") or "").lower()
    session = (env.get("XDG_SESSION_DESKTOP") or "").lower()

    if "drift" in desktop or "drift" in session:
        return "driftwm"
    if "hyprland" in desktop or "hypr" in session or env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return "hyprland"
    if "sway" in desktop or "sway" in session or env.get("SWAYSOCK"):
        return "sway"
    if "niri" in desktop or "niri" in session:
        return "niri"
    if "mango" in desktop or "mango" in session:
        return "mango"
    if "umbriel" in desktop or "umbriel" in session or env.get("UMBRIEL_SOCKET"):
        return "umbriel"

    # 2. Running processes
    for comp in ["driftwm", "hyprland", "sway", "niri", "mango", "umbriel"]:
        try:
            res = subprocess.run(["pgrep", "-x", comp], capture_output=True, text=True)
            if res.returncode == 0:
                return comp
        except Exception:
            pass

    return "generic"

def update_serpantinum_settings(name, resolution, framerate=None, scale=None):
    try:
        settings_path = Path.home() / ".config" / "serpantinum" / "settings.json"
        data = {}
        if settings_path.exists():
            with open(settings_path, "r", encoding="utf-8") as f:
                data = json.load(f)

        if "display" not in data or not isinstance(data["display"], dict):
            data["display"] = {"monitors": {}}
        if "monitors" not in data["display"] or not isinstance(data["display"]["monitors"], dict):
            data["display"]["monitors"] = {}

        mon_entry = data["display"]["monitors"].get(name, {})
        if not isinstance(mon_entry, dict):
            mon_entry = {}

        if resolution:
            mon_entry["resolution"] = str(resolution)
        if framerate:
            mon_entry["framerate"] = str(framerate)
        if scale is not None:
            mon_entry["scale"] = float(scale)

        data["display"]["monitors"][name] = mon_entry

        settings_path.parent.mkdir(parents=True, exist_ok=True)
        with open(settings_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to update serpantinum settings: {e}\n")

def apply_driftwm(name, resolution, framerate, scale, env):
    config_file = Path.home() / ".config" / "driftwm" / "config.toml"
    rate_str = f"@{framerate}" if framerate else "@60"
    mode_str = f"{resolution}{rate_str}" if resolution else "preferred"
    scale_val = float(scale) if scale is not None else 1.0

    if config_file.exists():
        try:
            text = config_file.read_text(encoding="utf-8")
            esc_name = re.escape(name)
            pattern = rf'(\[\[outputs\]\](?:(?!\n\[).)*?name\s*=\s*"{esc_name}"(?:(?!\n\[).)*)'
            match = re.search(pattern, text, re.DOTALL)

            if match:
                block = match.group(1)
                if resolution:
                    if re.search(r'\bmode\s*=', block):
                        block = re.sub(r'mode\s*=\s*"[^"]*"', f'mode = "{mode_str}"', block)
                    else:
                        block = block.rstrip() + f'\nmode = "{mode_str}"\n'
                if scale is not None:
                    if re.search(r'\bscale\s*=', block):
                        block = re.sub(r'scale\s*=\s*[0-9.]+', f'scale = {scale_val}', block)
                    else:
                        block = block.rstrip() + f'\nscale = {scale_val}\n'
                text = text[:match.start()] + block + text[match.end():]
            else:
                out_block = f'\n[[outputs]]\nname = "{name}"\nscale = {scale_val}\nposition = "auto"\nmode = "{mode_str}"\n'
                kb_match = re.search(r'\n\[keybindings\]', text)
                if kb_match:
                    pos = kb_match.start()
                    text = text[:pos] + out_block + text[pos:]
                else:
                    text = text.rstrip() + "\n" + out_block

            config_file.write_text(text, encoding="utf-8")
        except Exception as e:
            sys.stderr.write(f"Warning: failed to update driftwm config.toml: {e}\n")

    # Apply live mode via wlr-randr first if available
    if resolution:
        wlr_cmds = [
            ["wlr-randr", "--output", name, "--mode", f"{resolution}@{framerate}Hz", "--scale", str(scale_val)],
            ["wlr-randr", "--output", name, "--mode", f"{resolution}@{framerate}", "--scale", str(scale_val)],
            ["wlr-randr", "--output", name, "--mode", str(resolution), "--scale", str(scale_val)]
        ]
        applied = False
        for cmd in wlr_cmds:
            try:
                res = subprocess.run(cmd, env=env, capture_output=True, timeout=2)
                if res.returncode == 0:
                    applied = True
                    break
            except Exception:
                pass

    # Instruct driftwm to reload config and lock in the output mode
    try:
        subprocess.run(["driftwm", "msg", "action", "reload-config"], env=env, capture_output=True, timeout=2)
    except Exception:
        pass

def resolve_current_resolution(name, env):
    try:
        from monitors_detector import get_wlr_randr, get_hyprland_monitors
        monitors = get_wlr_randr(env) or get_hyprland_monitors(env)
        for m in (monitors or []):
            if m.get("name") == name:
                cur_mode = next((mode for mode in m.get("modes", []) if mode.get("current")), None)
                if not cur_mode and m.get("modes"):
                    cur_mode = m["modes"][0]
                if cur_mode and cur_mode.get("width") and cur_mode.get("height"):
                    return f"{cur_mode['width']}x{cur_mode['height']}"
                if m.get("width") and m.get("height"):
                    return f"{m['width']}x{m['height']}"
    except Exception:
        pass
    return None

def apply_hyprland(name, resolution, framerate, scale, env):
    if not resolution:
        resolution = resolve_current_resolution(name, env)
    rate_str = f"@{framerate}" if framerate else ""
    mode_str = f"{resolution}{rate_str}" if resolution else "preferred"
    scale_val = float(scale) if scale is not None else 1.0

    # 1. Live apply via wlr-randr (standard Wayland protocol supported across compositors)
    if resolution:
        wlr_cmds = []
        if framerate:
            try:
                wproc = subprocess.run(["wlr-randr", "--json"], env=env, capture_output=True, text=True, timeout=2)
                if wproc.returncode == 0:
                    for out in json.loads(wproc.stdout):
                        if out.get("name") == name:
                            for m in out.get("modes", []):
                                m_res = f"{m.get('width')}x{m.get('height')}"
                                if m_res == str(resolution) and round(float(m.get("refresh", 0))) == round(float(framerate)):
                                    wlr_cmds.append(["wlr-randr", "--output", name, "--mode", f"{m_res}@{m.get('refresh')}Hz", "--scale", str(scale_val)])
                                    break
            except Exception:
                pass
            wlr_cmds.append(["wlr-randr", "--output", name, "--custom-mode", f"{resolution}@{framerate}Hz", "--scale", str(scale_val)])
            wlr_cmds.append(["wlr-randr", "--output", name, "--mode", f"{resolution}@{framerate}Hz", "--scale", str(scale_val)])
        wlr_cmds.append(["wlr-randr", "--output", name, "--mode", str(resolution), "--scale", str(scale_val)])
        for wcmd in wlr_cmds:
            try:
                res = subprocess.run(wcmd, env=env, capture_output=True, timeout=2)
                if res.returncode == 0:
                    break
            except Exception:
                pass

    # 2. Also try hyprctl keyword monitor
    cmd = ["hyprctl", "keyword", "monitor", f"{name},{mode_str},auto,{scale_val}"]
    try:
        subprocess.run(cmd, env=env, capture_output=True, timeout=2)
    except Exception:
        pass

    # 2. Persist to ~/.config/hypr/default/monitors.lua
    cfg_path = Path.home() / ".config" / "hypr" / "default" / "monitors.lua"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        content = (
            '-- Autogenerated monitors configuration for Serpantinum\n\n'
            f'hl.monitor({{\n'
            f'    output = "{name}",\n'
            f'    mode = "{mode_str}",\n'
            f'    position = "auto",\n'
            f'    scale = {scale_val},\n'
            f'}})\n'
        )
        cfg_path.write_text(content, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write hyprland monitors.lua: {e}\n")

def apply_sway(name, resolution, framerate, scale, env):
    if not resolution:
        resolution = resolve_current_resolution(name, env)
    rate_str = f"@{framerate}Hz" if framerate else "@60Hz"
    mode_str = f"{resolution}{rate_str}" if resolution else ""
    scale_val = float(scale) if scale is not None else 1.0

    # Live apply
    if resolution:
        try:
            subprocess.run(["swaymsg", "output", name, "mode", mode_str], env=env, capture_output=True, timeout=2)
        except Exception:
            pass
    if scale is not None:
        try:
            subprocess.run(["swaymsg", "output", name, "scale", str(scale_val)], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

    # Persist to ~/.config/sway/default/monitors
    cfg_path = Path.home() / ".config" / "sway" / "default" / "monitors"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        mode_part = f"mode {mode_str} " if mode_str else ""
        content = (
            '# Autogenerated monitor configuration for Serpantinum\n'
            f'output "{name}" {{\n'
            f'    {mode_part}scale {scale_val}\n'
            '}\n'
        )
        cfg_path.write_text(content, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write sway monitors config: {e}\n")

def apply_niri(name, resolution, framerate, scale, env):
    rate_str = f"@{framerate}" if framerate else "@60"
    mode_str = f"{resolution}{rate_str}" if resolution else ""
    scale_val = float(scale) if scale is not None else 1.0

    # Live apply
    if resolution:
        try:
            subprocess.run(["niri", "msg", "output", name, "mode", mode_str], env=env, capture_output=True, timeout=2)
        except Exception:
            pass
    if scale is not None:
        try:
            subprocess.run(["niri", "msg", "output", name, "scale", str(scale_val)], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

    # Persist to ~/.config/niri/default/monitors.kdl
    cfg_path = Path.home() / ".config" / "niri" / "default" / "monitors.kdl"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        mode_line = f'    mode "{mode_str}"\n' if mode_str else ""
        content = (
            '// Autogenerated monitors configuration for Serpantinum\n'
            f'output "{name}" {{\n'
            f'{mode_line}'
            f'    scale {scale_val}\n'
            '}\n'
        )
        cfg_path.write_text(content, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write niri monitors.kdl: {e}\n")

def apply_mango(name, resolution, framerate, scale, env):
    mode_str = f"{resolution}@{framerate}" if framerate and resolution else (resolution or "")
    scale_val = float(scale) if scale is not None else 1.0

    if resolution:
        try:
            subprocess.run(["mmsg", "dispatch", f"output {name} mode {mode_str}"], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

    cfg_path = Path.home() / ".config" / "mango" / "default" / "monitors.conf"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        content = (
            '# Autogenerated monitor configuration for Serpantinum\n'
            f'monitor={name},{mode_str},auto,{scale_val}\n'
        )
        cfg_path.write_text(content, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write mango monitors.conf: {e}\n")

def apply_umbriel(name, resolution, framerate, scale, env):
    mode_str = f"{resolution}@{framerate}" if framerate and resolution else (resolution or "")
    scale_val = float(scale) if scale is not None else 1.0

    # Native config command persists the setting in ~/.config/umbriel.
    try:
        if mode_str:
            subprocess.run(["umbriel", "config", "set", f'output."{name}".mode', mode_str], env=env, capture_output=True, timeout=2)
        if scale is not None:
            subprocess.run(["umbriel", "config", "set", f'output."{name}".scale', str(scale_val)], env=env, capture_output=True, timeout=2)
    except Exception:
        pass

    # Fallback live apply for running sessions.
    try:
        if mode_str:
            subprocess.run(["wlr-randr", "--output", name, "--mode", mode_str, "--scale", str(scale_val)], env=env, capture_output=True, timeout=2)
        elif scale is not None:
            subprocess.run(["wlr-randr", "--output", name, "--scale", str(scale_val)], env=env, capture_output=True, timeout=2)
    except Exception:
        pass

def apply_generic(name, resolution, framerate, scale, env):
    scale_val = float(scale) if scale is not None else 1.0
    if resolution:
        wlr_cmds = [
            ["wlr-randr", "--output", name, "--mode", f"{resolution}@{framerate}Hz", "--scale", str(scale_val)],
            ["wlr-randr", "--output", name, "--mode", f"{resolution}@{framerate}", "--scale", str(scale_val)],
            ["wlr-randr", "--output", name, "--mode", str(resolution), "--scale", str(scale_val)]
        ]
        for cmd in wlr_cmds:
            try:
                res = subprocess.run(cmd, env=env, capture_output=True, timeout=2)
                if res.returncode == 0:
                    break
            except Exception:
                pass
    elif scale is not None:
        try:
            subprocess.run(["wlr-randr", "--output", name, "--scale", str(scale_val)], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

def main():
    parser = argparse.ArgumentParser(description="Serpantinum Monitor Manager")
    subparsers = parser.add_subparsers(dest="action", required=True)

    set_parser = subparsers.add_parser("set", help="Set and persist monitor configuration")
    set_parser.add_argument("--name", required=True, help="Output name, e.g. eDP-1")
    set_parser.add_argument("--resolution", help="Resolution WxH, e.g. 1920x1080")
    set_parser.add_argument("--framerate", help="Refresh rate in Hz, e.g. 60")
    set_parser.add_argument("--scale", type=float, help="Scale factor, e.g. 1.0")
    set_parser.add_argument("--compositor", help="Override target compositor")

    args = parser.parse_args()
    env = get_wayland_env()
    comp = (args.compositor or detect_compositor(env)).lower()

    if args.action == "set":
        # 1. Update serpantinum global config
        update_serpantinum_settings(args.name, args.resolution, args.framerate, args.scale)

        # 2. Dispatch to specific compositor handler
        if comp == "driftwm":
            apply_driftwm(args.name, args.resolution, args.framerate, args.scale, env)
        elif comp == "hyprland":
            apply_hyprland(args.name, args.resolution, args.framerate, args.scale, env)
        elif comp == "sway":
            apply_sway(args.name, args.resolution, args.framerate, args.scale, env)
        elif comp == "niri":
            apply_niri(args.name, args.resolution, args.framerate, args.scale, env)
        elif comp == "mango":
            apply_mango(args.name, args.resolution, args.framerate, args.scale, env)
        elif comp == "umbriel":
            apply_umbriel(args.name, args.resolution, args.framerate, args.scale, env)
        else:
            apply_generic(args.name, args.resolution, args.framerate, args.scale, env)

        print(json.dumps({"success": True, "compositor": comp, "output": args.name}))

if __name__ == "__main__":
    main()
