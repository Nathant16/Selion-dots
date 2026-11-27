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
        candidates = [
            sock for sock in glob.glob(f"{runtime_dir}/wayland-*")
            if not sock.endswith(".lock") and os.path.exists(sock)
        ]
        if candidates:
            candidates.sort(
                key=lambda s: (os.path.exists(f"{s}.lock"), os.path.getmtime(s)),
                reverse=True,
            )
            env["WAYLAND_DISPLAY"] = os.path.basename(candidates[0])

    if not env.get("HYPRLAND_INSTANCE_SIGNATURE") and os.path.exists(f"{runtime_dir}/hypr"):
        socks = glob.glob(f"{runtime_dir}/hypr/*/.socket.sock")
        if socks:
            newest_sock = max(socks, key=os.path.getmtime)
            env["HYPRLAND_INSTANCE_SIGNATURE"] = os.path.basename(os.path.dirname(newest_sock))

    if not env.get("SWAYSOCK"):
        sw_socks = glob.glob(f"{runtime_dir}/sway-ipc.*.sock")
        if sw_socks:
            env["SWAYSOCK"] = max(sw_socks, key=os.path.getmtime)

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

def _normalize_scale(scale):
    """Clamp and round display scale factor to avoid floating-point noise."""
    if scale is None:
        return 1.0
    val = max(0.5, min(3.0, round(float(scale), 4)))
    return val


def apply_driftwm(name, resolution, framerate, scale, env):
    explicit_mode = bool(resolution or framerate)
    config_file = Path.home() / ".config" / "driftwm" / "config.toml"
    rate_str = f"@{framerate}" if framerate else "@60"
    mode_str = f"{resolution}{rate_str}" if resolution else "preferred"
    scale_val = _normalize_scale(scale)

    if config_file.exists():
        try:
            text = config_file.read_text(encoding="utf-8")
            esc_name = re.escape(name)
            pattern = rf'(\[\[outputs\]\](?:(?!\n\[).)*?name\s*=\s*"{esc_name}"(?:(?!\n\[).)*)'
            match = re.search(pattern, text, re.DOTALL)

            if match:
                block = match.group(1)
                if explicit_mode and resolution:
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

    # Apply live mode/scale via wlr-randr when available without resetting mode on scale-only changes
    _apply_wlr_randr(name, resolution if explicit_mode else None, framerate if explicit_mode else None, scale_val, env)

    # Instruct driftwm to reload config and lock in the output mode
    try:
        subprocess.run(["driftwm", "msg", "action", "reload-config"], env=env, capture_output=True, timeout=2)
    except Exception:
        pass

def _resolve_current_mode(name, env):
    try:
        from monitors_detector import get_wlr_randr, get_hyprland_monitors
        monitors = get_wlr_randr(env) or get_hyprland_monitors(env)
        for m in (monitors or []):
            if m.get("name") == name:
                cur_mode = next((mode for mode in m.get("modes", []) if mode.get("current")), None)
                if not cur_mode and m.get("modes"):
                    cur_mode = m["modes"][0]
                return m, cur_mode
    except Exception:
        pass
    return None, None


def resolve_current_resolution(name, env):
    m, cur_mode = _resolve_current_mode(name, env)
    if cur_mode and cur_mode.get("width") and cur_mode.get("height"):
        return f"{cur_mode['width']}x{cur_mode['height']}"
    if m and m.get("width") and m.get("height"):
        return f"{m['width']}x{m['height']}"
    return None


def resolve_current_framerate(name, env):
    _, cur_mode = _resolve_current_mode(name, env)
    if cur_mode and cur_mode.get("refresh"):
        return str(int(round(float(cur_mode["refresh"]))))
    return None


def _apply_wlr_randr(name, resolution, framerate, scale_val, env):
    """Apply mode and/or scale dynamically via wlr-randr."""
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
            wlr_cmds.append(["wlr-randr", "--output", name, "--mode", f"{resolution}@{framerate}", "--scale", str(scale_val)])
        wlr_cmds.append(["wlr-randr", "--output", name, "--mode", str(resolution), "--scale", str(scale_val)])
        for wcmd in wlr_cmds:
            try:
                res = subprocess.run(wcmd, env=env, capture_output=True, timeout=2)
                if res.returncode == 0:
                    return True
            except Exception:
                pass
    elif scale_val is not None:
        try:
            res = subprocess.run(["wlr-randr", "--output", name, "--scale", str(scale_val)], env=env, capture_output=True, timeout=2)
            return res.returncode == 0
        except Exception:
            pass
    return False


def _find_brace_blocks(text, header_re):
    """Find top-level header { ... } spans in brace-delimited configs."""
    spans = []
    pos = 0
    while pos < len(text):
        m = header_re.search(text, pos)
        if not m:
            break
        start = m.start()
        brace_idx = text.find("{", m.end() - 1)
        if brace_idx == -1:
            break
        depth = 0
        i = brace_idx
        in_str = False
        esc = False
        while i < len(text):
            ch = text[i]
            if esc:
                esc = False
            elif ch == "\\" and in_str:
                esc = True
            elif ch == '"':
                in_str = not in_str
            elif not in_str:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        end = i + 1
                        if end < len(text) and text[end] == "\n":
                            end += 1
                        spans.append((start, end, text[start:end]))
                        pos = end
                        break
            i += 1
        else:
            break
    return spans


def _upsert_brace_block(text, header_re, match_name_fn, new_block, default_header, drop_placeholder_fn=None):
    """Update or insert one named block inside a brace-delimited config while keeping other blocks."""
    spans = _find_brace_blocks(text, header_re)
    if not spans:
        prefix = text.rstrip()
        if not prefix:
            prefix = default_header.rstrip()
        return prefix + "\n\n" + new_block.rstrip() + "\n", ""

    pieces = []
    last = 0
    replaced = False
    replaced_old = ""
    for start, end, blk in spans:
        pieces.append(text[last:start])
        if drop_placeholder_fn and drop_placeholder_fn(blk):
            last = end
            continue
        if match_name_fn(blk):
            if not replaced:
                pieces.append(new_block.rstrip() + "\n\n")
                replaced = True
                replaced_old = blk
        else:
            pieces.append(blk if blk.endswith("\n") else blk + "\n")
        last = end
    pieces.append(text[last:])

    out = "".join(pieces)
    if not replaced:
        out = out.rstrip() + "\n\n" + new_block.rstrip() + "\n"
    out = re.sub(r"\n{3,}", "\n\n", out).rstrip() + "\n"
    return out, replaced_old


def apply_hyprland(name, resolution, framerate, scale, env):
    explicit_mode = bool(resolution or framerate)
    if not resolution:
        resolution = resolve_current_resolution(name, env)
    if not framerate:
        framerate = resolve_current_framerate(name, env)
    rate_str = f"@{framerate}" if framerate else ""
    mode_str = f"{resolution}{rate_str}" if resolution else "preferred"
    scale_val = _normalize_scale(scale)

    # 1. Persist first / check existing block position cleanly
    cfg_path = Path.home() / ".config" / "hypr" / "default" / "monitors.lua"
    position_str = "auto"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""

    call_re = re.compile(r'^[ \t]*hl\.monitor\(\s*\{', re.MULTILINE)
    spans = []
    pos = 0
    while pos < len(existing):
        m = call_re.search(existing, pos)
        if not m:
            break
        start = m.start()
        paren_idx = existing.find("(", m.start())
        depth = 0
        i = paren_idx
        in_str = False
        esc = False
        while i < len(existing):
            ch = existing[i]
            if esc:
                esc = False
            elif ch == "\\" and in_str:
                esc = True
            elif ch in ('"', "'") and not in_str:
                quote_char = ch
                in_str = True
            elif in_str and ch == quote_char:
                in_str = False
            elif not in_str:
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        end = i + 1
                        if end < len(existing) and existing[end] == "\n":
                            end += 1
                        spans.append((start, end, existing[start:end]))
                        pos = end
                        break
            i += 1
        else:
            break

    esc_name = re.escape(name)
    for _, _, blk in spans:
        if re.search(rf'output\s*=\s*["\']{esc_name}["\']', blk):
            pm = re.search(r'position\s*=\s*["\']([^"\']+)["\']', blk)
            if pm:
                position_str = pm.group(1)
            if not resolution:
                mm = re.search(r'mode\s*=\s*["\']([^"\']+)["\']', blk)
                if mm:
                    mode_str = mm.group(1)
            break

    # 2. Live apply natively via hyprctl keyword monitor (fallback to wlr-randr only if needed)
    hypr_ok = False
    try:
        res = subprocess.run(
            ["hyprctl", "keyword", "monitor", f"{name},{mode_str},{position_str},{scale_val}"],
            env=env, capture_output=True, timeout=2
        )
        hypr_ok = (res.returncode == 0)
    except Exception:
        pass
    if not hypr_ok:
        _apply_wlr_randr(name, resolution if explicit_mode else None, framerate if explicit_mode else None, scale_val, env)

    # 3. Persist only this monitor in ~/.config/hypr/default/monitors.lua
    new_blk = (
        f'hl.monitor({{\n'
        f'    output = "{name}",\n'
        f'    mode = "{mode_str}",\n'
        f'    position = "{position_str}",\n'
        f'    scale = {scale_val},\n'
        f'}})\n'
    )
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        if not spans:
            header = existing.rstrip() or "-- Autogenerated monitors configuration for Serpantinum"
            updated = header + "\n\n" + new_blk
        else:
            pieces = []
            last = 0
            replaced = False
            for start, end, blk in spans:
                pieces.append(existing[last:start])
                if re.search(r'output\s*=\s*["\']\s*["\']', blk):
                    last = end
                    continue
                if re.search(rf'output\s*=\s*["\']{esc_name}["\']', blk):
                    if not replaced:
                        pieces.append(new_blk + "\n")
                        replaced = True
                else:
                    pieces.append(blk if blk.endswith("\n") else blk + "\n")
                last = end
            pieces.append(existing[last:])
            updated = "".join(pieces)
            if not replaced:
                updated = updated.rstrip() + "\n\n" + new_blk
            updated = re.sub(r"\n{3,}", "\n\n", updated).rstrip() + "\n"
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write hyprland monitors.lua: {e}\n")


def apply_sway(name, resolution, framerate, scale, env):
    explicit_mode = bool(resolution or framerate)
    if not resolution:
        resolution = resolve_current_resolution(name, env)
    if not framerate:
        framerate = resolve_current_framerate(name, env)
    rate_str = f"@{framerate}Hz" if framerate else ""
    mode_str = f"{resolution}{rate_str}" if resolution else ""
    scale_val = _normalize_scale(scale)

    # Live apply (skip mode re-set on scale-only changes to prevent screen flicker)
    if explicit_mode and mode_str:
        try:
            subprocess.run(["swaymsg", "output", name, "mode", mode_str], env=env, capture_output=True, timeout=2)
        except Exception:
            pass
    if scale is not None:
        try:
            subprocess.run(["swaymsg", "output", name, "scale", str(scale_val)], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

    # Persist to ~/.config/sway/default/monitors without clobbering other outputs
    cfg_path = Path.home() / ".config" / "sway" / "default" / "monitors"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
        esc_name = re.escape(name)
        header_re = re.compile(r'^[ \t]*output\s+(?:"[^"]+"|\S+)\s*\{', re.MULTILINE)
        mode_part = f"    mode {mode_str}\n" if mode_str else ""
        new_block = (
            f'output "{name}" {{\n'
            f'{mode_part}'
            f'    scale {scale_val}\n'
            f'    adaptive_sync off\n'
            f'    render_bit_depth 8\n'
            f'    allow_tearing no\n'
            f'}}\n'
        )
        updated, _ = _upsert_brace_block(
            existing,
            header_re,
            lambda b: bool(re.match(rf'^[ \t]*output\s+"?{esc_name}"?\s*\{{', b)),
            new_block,
            "# Autogenerated monitor configuration for Serpantinum",
        )
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write sway monitors config: {e}\n")


def apply_niri(name, resolution, framerate, scale, env):
    explicit_mode = bool(resolution or framerate)
    if not resolution:
        resolution = resolve_current_resolution(name, env)
    if not framerate:
        framerate = resolve_current_framerate(name, env)
    rate_str = f"@{framerate}" if framerate else ""
    mode_str = f"{resolution}{rate_str}" if resolution else ""
    scale_val = _normalize_scale(scale)

    # Live apply (skip mode re-set on scale-only changes)
    if explicit_mode and resolution:
        live_mode = f"{resolution}@{float(framerate):.3f}" if framerate else str(resolution)
        for mcmd in (
            ["niri", "msg", "output", name, "mode", live_mode],
            ["niri", "msg", "output", name, "mode", mode_str],
            ["niri", "msg", "output", name, "mode", str(resolution)],
        ):
            try:
                res = subprocess.run(mcmd, env=env, capture_output=True, timeout=2)
                if res.returncode == 0:
                    break
            except Exception:
                pass
    if scale is not None:
        try:
            subprocess.run(["niri", "msg", "output", name, "scale", str(scale_val)], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

    # Persist to ~/.config/niri/default/monitors.kdl without clobbering other outputs
    cfg_path = Path.home() / ".config" / "niri" / "default" / "monitors.kdl"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
        esc_name = re.escape(name)
        header_re = re.compile(r'^[ \t]*output\s+"[^"]+"\s*\{', re.MULTILINE)
        mode_line = f'    mode "{mode_str}"\n' if mode_str else ""
        new_block = (
            f'output "{name}" {{\n'
            f'{mode_line}'
            f'    scale {scale_val}\n'
            f'}}\n'
        )
        updated, _ = _upsert_brace_block(
            existing,
            header_re,
            lambda b: bool(re.match(rf'^[ \t]*output\s+"{esc_name}"\s*\{{', b)),
            new_block,
            "// Autogenerated monitors configuration for Serpantinum",
        )
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write niri monitors.kdl: {e}\n")


def apply_mango(name, resolution, framerate, scale, env):
    explicit_mode = bool(resolution or framerate)
    scale_val = _normalize_scale(scale)
    if abs(scale_val - round(scale_val)) < 1e-6:
        scale_val = int(round(scale_val))

    _apply_wlr_randr(name, resolution if explicit_mode else None, framerate if explicit_mode else None, scale_val, env)

    if not resolution:
        resolution = resolve_current_resolution(name, env)
    if not framerate:
        framerate = resolve_current_framerate(name, env)

    cfg_path = Path.home() / ".config" / "mango" / "default" / "monitors.conf"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
        esc_name = re.escape(name)

        rule_parts = [f"name:{name}"]
        if resolution and "x" in str(resolution):
            w, h = str(resolution).split("x", 1)
            rule_parts.extend([f"width:{w}", f"height:{h}"])
        if framerate:
            rule_parts.append(f"refresh:{int(round(float(framerate)))}")
        rule_parts.append(f"scale:{scale_val}")
        new_line = "monitor_rule=" + ",".join(rule_parts)

        lines = existing.splitlines()
        out_lines = []
        replaced = False
        line_re = re.compile(rf'^\s*(?:monitor_rule|monitor)\s*=(?:[^,\n]*,)?\s*(?:name:)?{esc_name}(?:,|$)')
        for line in lines:
            if line_re.search(line):
                if not replaced:
                    out_lines.append(new_line)
                    replaced = True
                continue
            out_lines.append(line)

        if not out_lines:
            out_lines = ["# Autogenerated monitor configuration for Serpantinum", new_line]
        elif not replaced:
            out_lines.append(new_line)

        cfg_path.write_text("\n".join(out_lines).rstrip() + "\n", encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write mango monitors.conf: {e}\n")


def apply_umbriel(name, resolution, framerate, scale, env):
    explicit_mode = bool(resolution or framerate)
    if not resolution:
        resolution = resolve_current_resolution(name, env)
    if not framerate:
        framerate = resolve_current_framerate(name, env)
    mode_str = f"{resolution}@{framerate}" if framerate and resolution else (resolution or "")
    scale_val = _normalize_scale(scale)

    # Live runtime overrides (lasts until exit in Umbriel).
    live_applied = False
    try:
        if explicit_mode and mode_str:
            r1 = subprocess.run(["umbriel", "config", "set", f'output."{name}".mode', mode_str], env=env, capture_output=True, timeout=2)
            live_applied = r1.returncode == 0
        if scale is not None:
            r2 = subprocess.run(["umbriel", "config", "set", f'output."{name}".scale', str(scale_val)], env=env, capture_output=True, timeout=2)
            live_applied = live_applied or (r2.returncode == 0)
    except Exception:
        pass

    if not live_applied:
        _apply_wlr_randr(name, resolution if explicit_mode else None, framerate if explicit_mode else None, scale_val, env)

    # Persist per-output configuration in ~/.config/umbriel/config/monitors.toml
    cfg_path = Path.home() / ".config" / "umbriel" / "config" / "monitors.toml"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
        esc_name = re.escape(name)
        header_re = re.compile(rf'^\[output\.(?:"{esc_name}"|{esc_name})\]\s*$', re.MULTILINE)
        lines = existing.splitlines()
        block_lines = [f'[output."{name}"]']
        if mode_str:
            block_lines.append(f'mode = "{mode_str}"')
        block_lines.append(f"scale = {scale_val}")
        block_lines.append("direct_scanout = false")
        block_lines.append('hdr = "off"')
        block_lines.append('vrr = "disabled"')
        block_lines.append("bit_depth = 8")
        block_lines.append("tearing = false")

        out_lines = []
        i = 0
        replaced = False
        while i < len(lines):
            if header_re.match(lines[i].strip()):
                i += 1
                existing_mode = ""
                while i < len(lines) and not lines[i].strip().startswith("["):
                    m_mode = re.match(r'^\s*mode\s*=\s*"([^"]*)"', lines[i])
                    if m_mode:
                        existing_mode = m_mode.group(1)
                    i += 1
                if not replaced:
                    if not mode_str and existing_mode:
                        block_lines.insert(1, f'mode = "{existing_mode}"')
                    out_lines.extend(block_lines)
                    replaced = True
                continue
            out_lines.append(lines[i])
            i += 1

        if not out_lines:
            out_lines = ["# Autogenerated monitor configuration for Serpantinum", ""] + block_lines
        elif not replaced:
            if out_lines and out_lines[-1].strip():
                out_lines.append("")
            out_lines.extend(block_lines)

        cfg_path.write_text("\n".join(out_lines).rstrip() + "\n", encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write umbriel monitors.toml: {e}\n")

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
