#!/usr/bin/env python3
"""
Serpantinum Unified Monitor Manager
Applies and persists display resolution, refresh rate, scaling, and 2D positions
across supported Wayland compositors:
- driftwm (~/.config/driftwm/config.toml)
- hyprland (~/.config/hypr/default/monitors.lua)
- sway (~/.config/sway/default/monitors)
- niri (~/.config/niri/default/monitors.kdl)
- mango (~/.config/mango/default/monitors.conf)
- umbriel (~/.config/umbriel/config/monitors.toml via umbriel config set)
- generic wlroots (wlr-randr)
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
_SHARE_SYS_DIR = Path.home() / ".local" / "share" / "serpantinum" / "src" / "scripts" / "system"
for _p in (_SCRIPT_DIR, _SHARE_SYS_DIR):
    if _p.is_dir() and str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

try:
    from monitors_detector import detect_monitors, get_running_compositors, get_wayland_env, get_wlr_randr
except Exception:
    detect_monitors = None
    get_running_compositors = None
    get_wayland_env = None
    get_wlr_randr = None


def _resolve_env():
    if get_wayland_env is not None:
        return get_wayland_env()
    env = dict(os.environ)
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return env


def _running_compositors():
    if get_running_compositors is not None:
        return get_running_compositors()
    found = set()
    try:
        res = subprocess.run(["ps", "-u", str(os.getuid()), "-o", "comm="], capture_output=True, text=True, timeout=2)
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                comm = line.strip().lower()
                if comm in ("driftwm", "hyprland", "sway", "niri", "mango", "umbriel"):
                    found.add(comm)
    except Exception:
        pass
    return found


def detect_compositor(env):
    running = _running_compositors()
    desktop = (env.get("XDG_CURRENT_DESKTOP") or "").lower()
    session = (env.get("XDG_SESSION_DESKTOP") or "").lower()

    def _alive(comp):
        return (not running) or (comp in running)

    for needle, comp in (
        ("drift", "driftwm"),
        ("hypr", "hyprland"),
        ("sway", "sway"),
        ("niri", "niri"),
        ("mango", "mango"),
        ("umbriel", "umbriel"),
    ):
        if (needle in desktop or needle in session) and _alive(comp):
            return comp

    if len(running) == 1:
        return next(iter(running))

    if _alive("hyprland") and env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return "hyprland"
    if _alive("sway") and env.get("SWAYSOCK"):
        return "sway"
    if _alive("niri") and env.get("NIRI_SOCKET"):
        return "niri"
    if _alive("umbriel") and env.get("UMBRIEL_SOCKET"):
        return "umbriel"

    for comp in ("driftwm", "hyprland", "sway", "niri", "mango", "umbriel"):
        if comp in running:
            return comp
    return "generic"


def _normalize_scale(scale):
    """Clamp and round display scale factor to avoid floating-point noise."""
    if scale is None:
        return 1.0
    return max(0.5, min(3.0, round(float(scale), 4)))


def _live_monitors_map(env):
    if detect_monitors is None:
        return {}
    try:
        items = detect_monitors(env)
        return {m["name"]: m for m in items if isinstance(m, dict) and m.get("name")}
    except Exception:
        return {}


def update_serpantinum_settings_batch(entries):
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

        for item in entries:
            name = item.get("name")
            if not name:
                continue
            mon_entry = data["display"]["monitors"].get(name, {})
            if not isinstance(mon_entry, dict):
                mon_entry = {}
            if item.get("resolution"):
                mon_entry["resolution"] = str(item["resolution"])
            if item.get("framerate"):
                mon_entry["framerate"] = str(item["framerate"])
            if item.get("scale") is not None:
                mon_entry["scale"] = float(item["scale"])
            if item.get("x") is not None:
                mon_entry["x"] = int(round(item["x"]))
            if item.get("y") is not None:
                mon_entry["y"] = int(round(item["y"]))
            if item.get("powerEnabled") is not None:
                mon_entry["powerEnabled"] = bool(item["powerEnabled"])
            data["display"]["monitors"][name] = mon_entry

        settings_path.parent.mkdir(parents=True, exist_ok=True)
        with open(settings_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to update serpantinum settings: {e}\n")


def _apply_wlr_randr(name, resolution, framerate, scale_val, env, pos=None):
    """Apply mode, scale, and/or position dynamically via wlr-randr."""
    pos_args = [f"--pos={int(pos[0])},{int(pos[1])}"] if pos is not None else []
    if resolution:
        wlr_cmds = []
        if framerate and get_wlr_randr is not None:
            try:
                for out in (get_wlr_randr(env) or []):
                    if out.get("name") == name:
                        for m in out.get("modes", []):
                            m_res = f"{m.get('width')}x{m.get('height')}"
                            if m_res == str(resolution) and round(float(m.get("refresh", 0))) == round(float(framerate)):
                                wlr_cmds.append(["wlr-randr", "--output", name, "--mode", f"{m_res}@{m.get('refresh')}Hz", "--scale", str(scale_val)] + pos_args)
                                break
            except Exception:
                pass
        if framerate:
            wlr_cmds.append(["wlr-randr", "--output", name, "--custom-mode", f"{resolution}@{framerate}Hz", "--scale", str(scale_val)] + pos_args)
            wlr_cmds.append(["wlr-randr", "--output", name, "--mode", f"{resolution}@{framerate}Hz", "--scale", str(scale_val)] + pos_args)
            wlr_cmds.append(["wlr-randr", "--output", name, "--mode", f"{resolution}@{framerate}", "--scale", str(scale_val)] + pos_args)
        wlr_cmds.append(["wlr-randr", "--output", name, "--mode", str(resolution), "--scale", str(scale_val)] + pos_args)
        for wcmd in wlr_cmds:
            try:
                res = subprocess.run(wcmd, env=env, capture_output=True, timeout=2)
                if res.returncode == 0:
                    return True
            except Exception:
                pass
        return False

    cmd = ["wlr-randr", "--output", name]
    if scale_val is not None:
        cmd.extend(["--scale", str(scale_val)])
    cmd.extend(pos_args)
    if len(cmd) > 3:
        try:
            res = subprocess.run(cmd, env=env, capture_output=True, timeout=2)
            return res.returncode == 0
        except Exception:
            pass
    return False


def _apply_wlr_randr_positions(items, env):
    cmd = ["wlr-randr"]
    for item in items:
        if item.get("name") and item.get("x") is not None and item.get("y") is not None:
            cmd.extend(["--output", item["name"], f"--pos={int(round(item['x']))},{int(round(item['y']))}"])
    if len(cmd) <= 1:
        return False
    try:
        res = subprocess.run(cmd, env=env, capture_output=True, timeout=3)
        return res.returncode == 0
    except Exception:
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
        prefix = text.rstrip() or default_header.rstrip()
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


def _find_hypr_spans(text):
    call_re = re.compile(r'^[ \t]*hl\.monitor\(\s*\{', re.MULTILINE)
    spans = []
    pos = 0
    while pos < len(text):
        m = call_re.search(text, pos)
        if not m:
            break
        start = m.start()
        paren_idx = text.find("(", m.start())
        depth = 0
        i = paren_idx
        in_str = False
        esc = False
        quote_char = '"'
        while i < len(text):
            ch = text[i]
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
                        if end < len(text) and text[end] == "\n":
                            end += 1
                        spans.append((start, end, text[start:end]))
                        pos = end
                        break
            i += 1
        else:
            break
    return spans


def _upsert_hypr_block(text, name, mode_str, pos_str, scale_val, disabled=False):
    spans = _find_hypr_spans(text)
    esc_name = re.escape(name)
    disabled_line = "    disabled = true,\n" if disabled else ""
    new_blk = (
        f'hl.monitor({{\n'
        f'    output = "{name}",\n'
        f'    mode = "{mode_str}",\n'
        f'    position = "{pos_str}",\n'
        f'    scale = {scale_val},\n'
        f'{disabled_line}'
        f'}})\n'
    )
    if not spans:
        header = text.rstrip() or "-- Autogenerated monitors configuration for Serpantinum"
        return header + "\n\n" + new_blk

    pieces = []
    last = 0
    replaced = False
    for start, end, blk in spans:
        pieces.append(text[last:start])
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
    pieces.append(text[last:])
    updated = "".join(pieces)
    if not replaced:
        updated = updated.rstrip() + "\n\n" + new_blk
    return re.sub(r"\n{3,}", "\n\n", updated).rstrip() + "\n"


def _set_toml_key(block, key, val_repr):
    if re.search(rf'(?m)^\s*{re.escape(key)}\s*=', block):
        return re.sub(rf'(?m)^\s*{re.escape(key)}\s*=\s*.*$', f'{key} = {val_repr}', block)
    return block.rstrip() + f'\n{key} = {val_repr}\n'


# ---- DriftWM ----

def _persist_driftwm_entry(text, name, mode_str, scale_val, pos_repr, update_mode=True, update_scale=True):
    esc_name = re.escape(name)
    pattern = rf'(\[\[outputs\]\](?:(?!\n\[).)*?name\s*=\s*"{esc_name}"(?:(?!\n\[).)*)'
    match = re.search(pattern, text, re.DOTALL)
    if match:
        block = match.group(1)
        if update_mode and mode_str:
            block = _set_toml_key(block, "mode", f'"{mode_str}"')
        if update_scale and scale_val is not None:
            block = _set_toml_key(block, "scale", f"{scale_val}")
        if pos_repr is not None:
            block = _set_toml_key(block, "position", pos_repr)
        return text[:match.start()] + block + text[match.end():]

    pos_line = pos_repr if pos_repr is not None else '"auto"'
    out_block = f'\n[[outputs]]\nname = "{name}"\nscale = {scale_val}\nposition = {pos_line}\nmode = "{mode_str or "preferred"}"\n'
    kb_match = re.search(r'\n\[keybindings\]', text)
    if kb_match:
        pos = kb_match.start()
        return text[:pos] + out_block + text[pos:]
    return text.rstrip() + "\n" + out_block


def apply_driftwm(name, resolution, framerate, scale, env, x=None, y=None):
    explicit_mode = bool(resolution or framerate)
    rate_str = f"@{framerate}" if framerate else "@60"
    mode_str = f"{resolution}{rate_str}" if resolution else "preferred"
    scale_val = _normalize_scale(scale)
    pos = (int(round(x)), int(round(y))) if (x is not None and y is not None) else None
    pos_repr = f"[{pos[0]}, {pos[1]}]" if pos is not None else None

    config_file = Path.home() / ".config" / "driftwm" / "config.toml"
    if config_file.exists():
        try:
            text = config_file.read_text(encoding="utf-8")
            text = _persist_driftwm_entry(text, name, mode_str if explicit_mode else None, scale_val, pos_repr, update_mode=explicit_mode)
            config_file.write_text(text, encoding="utf-8")
        except Exception as e:
            sys.stderr.write(f"Warning: failed to update driftwm config.toml: {e}\n")

    _apply_wlr_randr(name, resolution if explicit_mode else None, framerate if explicit_mode else None, scale_val, env, pos=pos)
    try:
        subprocess.run(["driftwm", "msg", "action", "reload-config"], env=env, capture_output=True, timeout=2)
    except Exception:
        pass


def apply_layout_driftwm(items, env, live_map):
    config_file = Path.home() / ".config" / "driftwm" / "config.toml"
    if config_file.exists():
        try:
            text = config_file.read_text(encoding="utf-8")
            for item in items:
                name = item["name"]
                live = live_map.get(name, {})
                res = item.get("resolution") or live.get("dimensions")
                rate = item.get("framerate") or live.get("framerate") or "60"
                mode_str = f"{res}@{rate}" if res else None
                sc = _normalize_scale(item["scale"] if item.get("scale") is not None else live.get("scale", 1.0))
                pos_repr = f"[{int(round(item['x']))}, {int(round(item['y']))}]"
                text = _persist_driftwm_entry(text, name, mode_str, sc, pos_repr, update_mode=bool(item.get("resolution")), update_scale=(item.get("scale") is not None))
            config_file.write_text(text, encoding="utf-8")
        except Exception as e:
            sys.stderr.write(f"Warning: failed to update driftwm config.toml layout: {e}\n")

    _apply_wlr_randr_positions(items, env)
    try:
        subprocess.run(["driftwm", "msg", "action", "reload-config"], env=env, capture_output=True, timeout=2)
    except Exception:
        pass


def apply_power_driftwm(name, enabled, res, rate, scale_val, pos, env):
    flag = "--on" if enabled else "--off"
    try:
        if enabled:
            cmd = ["wlr-randr", "--output", name, "--on", "--scale", str(scale_val)]
            if pos is not None:
                cmd.append(f"--pos={int(pos[0])},{int(pos[1])}")
            subprocess.run(cmd, env=env, capture_output=True, timeout=2)
            subprocess.run(["driftwm", "msg", "action", "reload-config"], env=env, capture_output=True, timeout=2)
        else:
            subprocess.run(["wlr-randr", "--output", name, flag], env=env, capture_output=True, timeout=2)
    except Exception:
        pass


# ---- Hyprland ----

def _hypr_existing_fields(text, name):
    esc_name = re.escape(name)
    pos_str = None
    mode_str = None
    scale_val = None
    disabled = False
    for _, _, blk in _find_hypr_spans(text):
        if re.search(rf'output\s*=\s*["\']{esc_name}["\']', blk):
            pm = re.search(r'position\s*=\s*["\']([^"\']+)["\']', blk)
            if pm:
                pos_str = pm.group(1)
            mm = re.search(r'mode\s*=\s*["\']([^"\']+)["\']', blk)
            if mm:
                mode_str = mm.group(1)
            sm = re.search(r'scale\s*=\s*([0-9.]+)', blk)
            if sm:
                scale_val = float(sm.group(1))
            dm = re.search(r'disabled\s*=\s*(true|false)', blk)
            if dm:
                disabled = (dm.group(1) == "true")
            break
    return mode_str, pos_str, scale_val, disabled


def _run_hyprctl_monitor(name, mode_str, pos_str, scale_val, env, disabled=None):
    safe_name = str(name).replace('"', '\\"')
    safe_mode = str(mode_str or "preferred").replace('"', '\\"')
    safe_pos = str(pos_str or "auto").replace('"', '\\"')
    fields = [
        f'output = "{safe_name}"',
        f'mode = "{safe_mode}"',
        f'position = "{safe_pos}"',
        f'scale = {scale_val}',
    ]
    if disabled is not None:
        fields.append(f'disabled = {"true" if disabled else "false"}')
    lua_cmd = "hl.monitor({ " + ", ".join(fields) + " })"
    try:
        r = subprocess.run(["hyprctl", "eval", lua_cmd], env=env, capture_output=True, text=True, timeout=2)
        if r.returncode == 0 and r.stdout.strip().lower() == "ok":
            return True
    except Exception:
        pass
    try:
        spec = f"{name},disable" if disabled else f"{name},{mode_str or 'preferred'},{pos_str or 'auto'},{scale_val}"
        r = subprocess.run(["hyprctl", "keyword", "monitor", spec], env=env, capture_output=True, text=True, timeout=2)
        return r.returncode == 0 and "unknown" not in (r.stdout + r.stderr).lower()
    except Exception:
        return False


def apply_hyprland(name, resolution, framerate, scale, env, x=None, y=None):
    explicit_mode = bool(resolution or framerate)
    live = _live_monitors_map(env).get(name, {})
    cfg_path = Path.home() / ".config" / "hypr" / "default" / "monitors.lua"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    old_mode, old_pos, _, old_disabled = _hypr_existing_fields(existing, name)
    is_disabled = (not live.get("active", True)) if live else old_disabled

    res = resolution or live.get("dimensions")
    rate = framerate or live.get("framerate")
    rate_str = f"@{rate}" if rate else ""
    mode_str = f"{res}{rate_str}" if res else (old_mode or "preferred")
    scale_val = _normalize_scale(scale)
    pos_str = f"{int(round(x))}x{int(round(y))}" if (x is not None and y is not None) else (old_pos or "auto")

    if not _run_hyprctl_monitor(name, mode_str, pos_str, scale_val, env, disabled=True if is_disabled else None):
        pos = (int(round(x)), int(round(y))) if (x is not None and y is not None) else None
        _apply_wlr_randr(name, resolution if explicit_mode else None, framerate if explicit_mode else None, scale_val, env, pos=pos)

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        updated = _upsert_hypr_block(existing, name, mode_str, pos_str, scale_val, disabled=is_disabled)
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write hyprland monitors.lua: {e}\n")


def apply_layout_hyprland(items, env, live_map):
    cfg_path = Path.home() / ".config" / "hypr" / "default" / "monitors.lua"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    updated = existing

    for item in items:
        name = item["name"]
        live = live_map.get(name, {})
        old_mode, _, old_scale, old_disabled = _hypr_existing_fields(updated, name)
        is_disabled = (not live.get("active", True)) if live else old_disabled
        res = item.get("resolution") or live.get("dimensions")
        rate = item.get("framerate") or live.get("framerate")
        mode_str = f"{res}@{rate}" if (res and rate) else (res or old_mode or "preferred")
        sc = _normalize_scale(item["scale"] if item.get("scale") is not None else (live.get("scale") if live.get("scale") is not None else (old_scale or 1.0)))
        pos_str = f"{int(round(item['x']))}x{int(round(item['y']))}"
        _run_hyprctl_monitor(name, mode_str, pos_str, sc, env, disabled=True if is_disabled else None)
        updated = _upsert_hypr_block(updated, name, mode_str, pos_str, sc, disabled=is_disabled)

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write hyprland monitors.lua layout: {e}\n")


def apply_power_hyprland(name, enabled, res, rate, scale_val, pos, env):
    cfg_path = Path.home() / ".config" / "hypr" / "default" / "monitors.lua"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    old_mode, old_pos, old_scale, _ = _hypr_existing_fields(existing, name)
    live = _live_monitors_map(env).get(name, {})
    eff_res = res or live.get("dimensions")
    eff_rate = rate or live.get("framerate")
    mode_str = f"{eff_res}@{eff_rate}" if (eff_res and eff_rate) else (old_mode or eff_res or "preferred")
    pos_str = f"{int(pos[0])}x{int(pos[1])}" if pos is not None else (old_pos or "auto")
    sc = _normalize_scale(scale_val if scale_val is not None else (old_scale or 1.0))

    _run_hyprctl_monitor(name, mode_str, pos_str, sc, env, disabled=(not enabled))
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        updated = _upsert_hypr_block(existing, name, mode_str, pos_str, sc, disabled=(not enabled))
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write hyprland monitors.lua power: {e}\n")


# ---- Sway ----

def _sway_existing_fields(text, name):
    esc_name = re.escape(name)
    header_re = re.compile(r'^[ \t]*output\s+(?:"[^"]+"|\S+)\s*\{', re.MULTILINE)
    for _, _, blk in _find_brace_blocks(text, header_re):
        if re.match(rf'^[ \t]*output\s+"?{esc_name}"?\s*\{{', blk):
            pm = re.search(r'^\s*(?:position|pos)\s+(-?\d+)\s+(-?\d+)', blk, re.MULTILINE)
            pos = (int(pm.group(1)), int(pm.group(2))) if pm else None
            dis = bool(re.search(r'^\s*disable\b', blk, re.MULTILINE))
            return pos, dis
    return None, False


def _sway_existing_pos(text, name):
    pos, _ = _sway_existing_fields(text, name)
    return pos


def _persist_sway_text(existing, name, mode_str, scale_val, pos, disabled=False):
    esc_name = re.escape(name)
    header_re = re.compile(r'^[ \t]*output\s+(?:"[^"]+"|\S+)\s*\{', re.MULTILINE)
    mode_part = f"    mode {mode_str}\n" if mode_str else ""
    pos_part = f"    position {int(pos[0])} {int(pos[1])}\n" if pos is not None else ""
    dis_part = "    disable\n" if disabled else ""
    new_block = (
        f'output "{name}" {{\n'
        f'{dis_part}'
        f'{mode_part}'
        f'{pos_part}'
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
    return updated


def apply_sway(name, resolution, framerate, scale, env, x=None, y=None):
    explicit_mode = bool(resolution or framerate)
    live = _live_monitors_map(env).get(name, {})
    res = resolution or live.get("dimensions")
    rate = framerate or live.get("framerate")
    rate_str = f"@{rate}Hz" if rate else ""
    mode_str = f"{res}{rate_str}" if res else ""
    scale_val = _normalize_scale(scale)

    cfg_path = Path.home() / ".config" / "sway" / "default" / "monitors"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    old_pos, old_disabled = _sway_existing_fields(existing, name)
    is_disabled = (not live.get("active", True)) if live else old_disabled
    pos = (int(round(x)), int(round(y))) if (x is not None and y is not None) else old_pos

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
    if x is not None and y is not None:
        try:
            subprocess.run(["swaymsg", "output", name, "position", str(int(round(x))), str(int(round(y)))], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(_persist_sway_text(existing, name, mode_str, scale_val, pos, disabled=is_disabled), encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write sway monitors config: {e}\n")


def apply_layout_sway(items, env, live_map):
    cfg_path = Path.home() / ".config" / "sway" / "default" / "monitors"
    updated = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    sway_cmds = []

    for item in items:
        name = item["name"]
        live = live_map.get(name, {})
        _, old_disabled = _sway_existing_fields(updated, name)
        is_disabled = (not live.get("active", True)) if live else old_disabled
        res = item.get("resolution") or live.get("dimensions")
        rate = item.get("framerate") or live.get("framerate")
        mode_str = f"{res}@{rate}Hz" if (res and rate) else (res or "")
        sc = _normalize_scale(item["scale"] if item.get("scale") is not None else live.get("scale", 1.0))
        pos = (int(round(item["x"])), int(round(item["y"])))
        sway_cmds.append(f'output "{name}" position {pos[0]} {pos[1]}')
        updated = _persist_sway_text(updated, name, mode_str, sc, pos, disabled=is_disabled)

    if sway_cmds:
        try:
            subprocess.run(["swaymsg", " ; ".join(sway_cmds)], env=env, capture_output=True, timeout=3)
        except Exception:
            pass

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write sway monitors config layout: {e}\n")


def apply_power_sway(name, enabled, res, rate, scale_val, pos, env):
    cfg_path = Path.home() / ".config" / "sway" / "default" / "monitors"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    old_pos, _ = _sway_existing_fields(existing, name)
    eff_pos = pos if pos is not None else old_pos
    mode_str = f"{res}@{rate}Hz" if (res and rate) else (res or "")
    sc = _normalize_scale(scale_val)

    try:
        cmds = [f'output "{name}" {"enable" if enabled else "disable"}']
        if enabled:
            if mode_str:
                cmds.append(f'output "{name}" mode {mode_str}')
            cmds.append(f'output "{name}" scale {sc}')
            if eff_pos is not None:
                cmds.append(f'output "{name}" position {int(eff_pos[0])} {int(eff_pos[1])}')
        subprocess.run(["swaymsg", " ; ".join(cmds)], env=env, capture_output=True, timeout=3)
    except Exception:
        pass

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(_persist_sway_text(existing, name, mode_str, sc, eff_pos, disabled=(not enabled)), encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write sway monitors config power: {e}\n")


# ---- Niri ----

def _niri_existing_fields(text, name):
    esc_name = re.escape(name)
    header_re = re.compile(r'^[ \t]*output\s+"[^"]+"\s*\{', re.MULTILINE)
    for _, _, blk in _find_brace_blocks(text, header_re):
        if re.match(rf'^[ \t]*output\s+"{esc_name}"\s*\{{', blk):
            pm = re.search(r'^\s*position\s+x=(-?\d+)\s+y=(-?\d+)', blk, re.MULTILINE)
            pos = (int(pm.group(1)), int(pm.group(2))) if pm else None
            off = bool(re.search(r'^\s*off\b', blk, re.MULTILINE))
            return pos, off
    return None, False


def _niri_existing_pos(text, name):
    pos, _ = _niri_existing_fields(text, name)
    return pos


def _persist_niri_text(existing, name, mode_str, scale_val, pos, disabled=False):
    esc_name = re.escape(name)
    header_re = re.compile(r'^[ \t]*output\s+"[^"]+"\s*\{', re.MULTILINE)
    off_line = "    off\n" if disabled else ""
    mode_line = f'    mode "{mode_str}"\n' if mode_str else ""
    pos_line = f'    position x={int(pos[0])} y={int(pos[1])}\n' if pos is not None else ""
    new_block = (
        f'output "{name}" {{\n'
        f'{off_line}'
        f'{mode_line}'
        f'    scale {scale_val}\n'
        f'{pos_line}'
        f'}}\n'
    )
    updated, _ = _upsert_brace_block(
        existing,
        header_re,
        lambda b: bool(re.match(rf'^[ \t]*output\s+"{esc_name}"\s*\{{', b)),
        new_block,
        "// Autogenerated monitors configuration for Serpantinum",
    )
    return updated


def apply_niri(name, resolution, framerate, scale, env, x=None, y=None):
    explicit_mode = bool(resolution or framerate)
    live = _live_monitors_map(env).get(name, {})
    res = resolution or live.get("dimensions")
    rate = framerate or live.get("framerate")
    rate_str = f"@{rate}" if rate else ""
    mode_str = f"{res}{rate_str}" if res else ""
    scale_val = _normalize_scale(scale)

    cfg_path = Path.home() / ".config" / "niri" / "default" / "monitors.kdl"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    old_pos, old_disabled = _niri_existing_fields(existing, name)
    is_disabled = (not live.get("active", True)) if live else old_disabled
    pos = (int(round(x)), int(round(y))) if (x is not None and y is not None) else old_pos

    if explicit_mode and res:
        live_mode = f"{res}@{float(rate):.3f}" if rate else str(res)
        for mcmd in (
            ["niri", "msg", "output", name, "mode", live_mode],
            ["niri", "msg", "output", name, "mode", mode_str],
            ["niri", "msg", "output", name, "mode", str(res)],
        ):
            try:
                r = subprocess.run(mcmd, env=env, capture_output=True, timeout=2)
                if r.returncode == 0:
                    break
            except Exception:
                pass
    if scale is not None:
        try:
            subprocess.run(["niri", "msg", "output", name, "scale", str(scale_val)], env=env, capture_output=True, timeout=2)
        except Exception:
            pass
    if x is not None and y is not None:
        try:
            subprocess.run(["niri", "msg", "output", name, "position", "set", "--", str(int(round(x))), str(int(round(y)))], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(_persist_niri_text(existing, name, mode_str, scale_val, pos, disabled=is_disabled), encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write niri monitors.kdl: {e}\n")


def apply_layout_niri(items, env, live_map):
    cfg_path = Path.home() / ".config" / "niri" / "default" / "monitors.kdl"
    updated = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""

    for item in items:
        name = item["name"]
        live = live_map.get(name, {})
        _, old_disabled = _niri_existing_fields(updated, name)
        is_disabled = (not live.get("active", True)) if live else old_disabled
        res = item.get("resolution") or live.get("dimensions")
        rate = item.get("framerate") or live.get("framerate")
        mode_str = f"{res}@{rate}" if (res and rate) else (res or "")
        sc = _normalize_scale(item["scale"] if item.get("scale") is not None else live.get("scale", 1.0))
        pos = (int(round(item["x"])), int(round(item["y"])))
        try:
            subprocess.run(["niri", "msg", "output", name, "position", "set", "--", str(pos[0]), str(pos[1])], env=env, capture_output=True, timeout=2)
        except Exception:
            pass
        updated = _persist_niri_text(updated, name, mode_str, sc, pos, disabled=is_disabled)

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write niri monitors.kdl layout: {e}\n")


def apply_power_niri(name, enabled, res, rate, scale_val, pos, env):
    cfg_path = Path.home() / ".config" / "niri" / "default" / "monitors.kdl"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    old_pos, _ = _niri_existing_fields(existing, name)
    eff_pos = pos if pos is not None else old_pos
    mode_str = f"{res}@{rate}" if (res and rate) else (res or "")
    sc = _normalize_scale(scale_val)

    try:
        subprocess.run(["niri", "msg", "output", name, "on" if enabled else "off"], env=env, capture_output=True, timeout=2)
        if enabled:
            subprocess.run(["niri", "msg", "output", name, "scale", str(sc)], env=env, capture_output=True, timeout=2)
            if eff_pos is not None:
                subprocess.run(["niri", "msg", "output", name, "position", "set", "--", str(int(eff_pos[0])), str(int(eff_pos[1]))], env=env, capture_output=True, timeout=2)
    except Exception:
        pass

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(_persist_niri_text(existing, name, mode_str, sc, eff_pos, disabled=(not enabled)), encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write niri monitors.kdl power: {e}\n")


# ---- Mango ----

def _mango_existing_fields(text, name):
    esc_name = re.escape(name)
    line_re = re.compile(rf'^\s*(?:monitor_rule|monitor)\s*=(?:[^,\n]*,)?\s*(?:name:)?{esc_name}(?:,|$)', re.MULTILINE)
    m = line_re.search(text)
    if m:
        line_start = text.rfind("\n", 0, m.start()) + 1
        line_end = text.find("\n", m.start())
        line = text[line_start:len(text) if line_end == -1 else line_end]
        xm = re.search(r'(?:^|,)\s*x:(-?\d+)', line)
        ym = re.search(r'(?:^|,)\s*y:(-?\d+)', line)
        pos = (int(xm.group(1)), int(ym.group(1))) if (xm and ym) else None
        dis = bool(re.search(r'(?:^|,)\s*disable:1(?:,|$)', line))
        return pos, dis
    return None, False


def _mango_existing_pos(text, name):
    pos, _ = _mango_existing_fields(text, name)
    return pos


def _persist_mango_text(existing, name, res, rate, scale_val, pos, disabled=False):
    if abs(scale_val - round(scale_val)) < 1e-6:
        scale_fmt = int(round(scale_val))
    else:
        scale_fmt = scale_val

    rule_parts = [f"name:{name}"]
    if res and "x" in str(res):
        w, h = str(res).split("x", 1)
        rule_parts.extend([f"width:{w}", f"height:{h}"])
    if rate:
        rule_parts.append(f"refresh:{int(round(float(rate)))}")
    rule_parts.append(f"scale:{scale_fmt}")
    if pos is not None:
        rule_parts.extend([f"x:{int(pos[0])}", f"y:{int(pos[1])}"])
    if disabled:
        rule_parts.append("disable:1")
    new_line = "monitor_rule=" + ",".join(rule_parts)

    esc_name = re.escape(name)
    line_re = re.compile(rf'^\s*(?:monitor_rule|monitor)\s*=(?:[^,\n]*,)?\s*(?:name:)?{esc_name}(?:,|$)')
    out_lines = []
    replaced = False
    for line in existing.splitlines():
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

    return "\n".join(out_lines).rstrip() + "\n"


def apply_mango(name, resolution, framerate, scale, env, x=None, y=None):
    explicit_mode = bool(resolution or framerate)
    scale_val = _normalize_scale(scale)
    live = _live_monitors_map(env).get(name, {})
    cfg_path = Path.home() / ".config" / "mango" / "default" / "monitors.conf"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""

    old_pos, old_disabled = _mango_existing_fields(existing, name)
    is_disabled = (not live.get("active", True)) if live else old_disabled
    pos = (int(round(x)), int(round(y))) if (x is not None and y is not None) else old_pos
    _apply_wlr_randr(name, resolution if explicit_mode else None, framerate if explicit_mode else None, scale_val, env, pos=(int(round(x)), int(round(y))) if (x is not None and y is not None) else None)

    res = resolution or live.get("dimensions")
    rate = framerate or live.get("framerate")
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(_persist_mango_text(existing, name, res, rate, scale_val, pos, disabled=is_disabled), encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write mango monitors.conf: {e}\n")


def apply_layout_mango(items, env, live_map):
    _apply_wlr_randr_positions(items, env)
    cfg_path = Path.home() / ".config" / "mango" / "default" / "monitors.conf"
    updated = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    for item in items:
        name = item["name"]
        live = live_map.get(name, {})
        _, old_disabled = _mango_existing_fields(updated, name)
        is_disabled = (not live.get("active", True)) if live else old_disabled
        res = item.get("resolution") or live.get("dimensions")
        rate = item.get("framerate") or live.get("framerate")
        sc = _normalize_scale(item["scale"] if item.get("scale") is not None else live.get("scale", 1.0))
        pos = (int(round(item["x"])), int(round(item["y"])))
        updated = _persist_mango_text(updated, name, res, rate, sc, pos, disabled=is_disabled)
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write mango monitors.conf layout: {e}\n")


def apply_power_mango(name, enabled, res, rate, scale_val, pos, env):
    cfg_path = Path.home() / ".config" / "mango" / "default" / "monitors.conf"
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    old_pos, _ = _mango_existing_fields(existing, name)
    eff_pos = pos if pos is not None else old_pos
    sc = _normalize_scale(scale_val)

    wlr_ok = False
    try:
        cmd = ["wlr-randr", "--output", name, "--on" if enabled else "--off"]
        if enabled:
            cmd.extend(["--scale", str(sc)])
            if eff_pos is not None:
                cmd.append(f"--pos={int(eff_pos[0])},{int(eff_pos[1])}")
        r = subprocess.run(cmd, env=env, capture_output=True, timeout=2)
        wlr_ok = (r.returncode == 0)
    except Exception:
        pass
    if not wlr_ok:
        try:
            subprocess.run(["mmsg", "dispatch", f"{'enable_monitor' if enabled else 'disable_monitor'},{name}"], env=env, capture_output=True, timeout=2)
        except Exception:
            pass

    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(_persist_mango_text(existing, name, res, rate, sc, eff_pos, disabled=(not enabled)), encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write mango monitors.conf power: {e}\n")


# ---- Umbriel ----

def _persist_umbriel_text(existing, name, mode_str, scale_val, pos, enabled=None):
    esc_name = re.escape(name)
    header_re = re.compile(rf'^\[output\.(?:"{esc_name}"|{esc_name})\]\s*$')
    lines = existing.splitlines()

    existing_mode = ""
    existing_pos = None
    existing_enabled = True
    i = 0
    while i < len(lines):
        if header_re.match(lines[i].strip()):
            j = i + 1
            while j < len(lines) and not lines[j].strip().startswith("["):
                m_mode = re.match(r'^\s*mode\s*=\s*"([^"]*)"', lines[j])
                if m_mode:
                    existing_mode = m_mode.group(1)
                m_pos = re.match(r'^\s*position\s*=\s*\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\]', lines[j])
                if m_pos:
                    existing_pos = (int(m_pos.group(1)), int(m_pos.group(2)))
                if re.match(r'^\s*enabled\s*=\s*false\b', lines[j]):
                    existing_enabled = False
                elif re.match(r'^\s*enabled\s*=\s*true\b', lines[j]):
                    existing_enabled = True
                j += 1
            break
        i += 1

    eff_mode = mode_str or existing_mode
    eff_pos = pos if pos is not None else existing_pos
    eff_enabled = existing_enabled if enabled is None else bool(enabled)
    block_lines = [f'[output."{name}"]']
    if not eff_enabled:
        block_lines.append("enabled = false")
    if eff_mode:
        block_lines.append(f'mode = "{eff_mode}"')
    block_lines.append(f"scale = {scale_val}")
    if eff_pos is not None:
        block_lines.append(f"position = [{eff_pos[0]}, {eff_pos[1]}]")
    block_lines.extend([
        "direct_scanout = false",
        'hdr = "off"',
        'vrr = "disabled"',
        "bit_depth = 8",
        "tearing = false",
    ])

    out_lines = []
    i = 0
    replaced = False
    while i < len(lines):
        if header_re.match(lines[i].strip()):
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("["):
                i += 1
            if not replaced:
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
    return "\n".join(out_lines).rstrip() + "\n"


def apply_umbriel(name, resolution, framerate, scale, env, x=None, y=None):
    explicit_mode = bool(resolution or framerate)
    live = _live_monitors_map(env).get(name, {})
    res = resolution or live.get("dimensions")
    rate = framerate or live.get("framerate")
    mode_str = f"{res}@{rate}" if rate and res else (res or "")
    scale_val = _normalize_scale(scale)
    pos = (int(round(x)), int(round(y))) if (x is not None and y is not None) else None
    is_enabled = live.get("active", True) if live else None

    live_applied = False
    try:
        if explicit_mode and mode_str:
            r1 = subprocess.run(["umbriel", "config", "set", f'output."{name}".mode', mode_str], env=env, capture_output=True, timeout=2)
            live_applied = (r1.returncode == 0)
        if scale is not None:
            r2 = subprocess.run(["umbriel", "config", "set", f'output."{name}".scale', str(scale_val)], env=env, capture_output=True, timeout=2)
            live_applied = live_applied or (r2.returncode == 0)
        if pos is not None:
            r3 = subprocess.run(["umbriel", "config", "set", f'output."{name}".position', f"[{pos[0]}, {pos[1]}]"], env=env, capture_output=True, timeout=2)
            live_applied = live_applied or (r3.returncode == 0)
    except Exception:
        pass

    if not live_applied:
        _apply_wlr_randr(name, resolution if explicit_mode else None, framerate if explicit_mode else None, scale_val, env, pos=pos)

    cfg_path = Path.home() / ".config" / "umbriel" / "config" / "monitors.toml"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
        cfg_path.write_text(_persist_umbriel_text(existing, name, mode_str, scale_val, pos, enabled=is_enabled), encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write umbriel monitors.toml: {e}\n")


def apply_layout_umbriel(items, env, live_map):
    fallback_items = []
    for item in items:
        name = item["name"]
        pos = (int(round(item["x"])), int(round(item["y"])))
        ok = False
        try:
            r = subprocess.run(["umbriel", "config", "set", f'output."{name}".position', f"[{pos[0]}, {pos[1]}]"], env=env, capture_output=True, timeout=2)
            ok = (r.returncode == 0)
        except Exception:
            pass
        if not ok:
            fallback_items.append(item)
    if fallback_items:
        _apply_wlr_randr_positions(fallback_items, env)

    cfg_path = Path.home() / ".config" / "umbriel" / "config" / "monitors.toml"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        updated = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
        for item in items:
            name = item["name"]
            live = live_map.get(name, {})
            res = item.get("resolution") or live.get("dimensions")
            rate = item.get("framerate") or live.get("framerate")
            mode_str = f"{res}@{rate}" if (res and rate) else (res or "")
            sc = _normalize_scale(item["scale"] if item.get("scale") is not None else live.get("scale", 1.0))
            pos = (int(round(item["x"])), int(round(item["y"])))
            is_enabled = live.get("active", True) if live else None
            updated = _persist_umbriel_text(updated, name, mode_str, sc, pos, enabled=is_enabled)
        cfg_path.write_text(updated, encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write umbriel monitors.toml layout: {e}\n")


def apply_power_umbriel(name, enabled, res, rate, scale_val, pos, env):
    mode_str = f"{res}@{rate}" if (res and rate) else (res or "")
    sc = _normalize_scale(scale_val)
    try:
        subprocess.run(["umbriel", "config", "set", f'output."{name}".enabled', "true" if enabled else "false"], env=env, capture_output=True, timeout=2)
        if enabled:
            subprocess.run(["umbriel", "msg", "output-enable", name], env=env, capture_output=True, timeout=2)
            if mode_str:
                subprocess.run(["umbriel", "config", "set", f'output."{name}".mode', mode_str], env=env, capture_output=True, timeout=2)
            subprocess.run(["umbriel", "config", "set", f'output."{name}".scale', str(sc)], env=env, capture_output=True, timeout=2)
            if pos is not None:
                subprocess.run(["umbriel", "config", "set", f'output."{name}".position', f"[{int(pos[0])}, {int(pos[1])}]"], env=env, capture_output=True, timeout=2)
        else:
            r = subprocess.run(["umbriel", "msg", "output-disable", name], env=env, capture_output=True, timeout=2)
            if r.returncode != 0:
                subprocess.run(["wlr-randr", "--output", name, "--off"], env=env, capture_output=True, timeout=2)
    except Exception:
        pass

    cfg_path = Path.home() / ".config" / "umbriel" / "config" / "monitors.toml"
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
        cfg_path.write_text(_persist_umbriel_text(existing, name, mode_str, sc, pos, enabled=enabled), encoding="utf-8")
    except Exception as e:
        sys.stderr.write(f"Warning: failed to write umbriel monitors.toml power: {e}\n")


# ---- Generic ----

def apply_generic(name, resolution, framerate, scale, env, x=None, y=None):
    pos = (int(round(x)), int(round(y))) if (x is not None and y is not None) else None
    _apply_wlr_randr(name, resolution, framerate, _normalize_scale(scale), env, pos=pos)


def apply_layout_generic(items, env, _live_map):
    _apply_wlr_randr_positions(items, env)


def apply_power_generic(name, enabled, res, rate, scale_val, pos, env):
    try:
        cmd = ["wlr-randr", "--output", name, "--on" if enabled else "--off"]
        if enabled:
            cmd.extend(["--scale", str(_normalize_scale(scale_val))])
            if pos is not None:
                cmd.append(f"--pos={int(pos[0])},{int(pos[1])}")
        subprocess.run(cmd, env=env, capture_output=True, timeout=2)
    except Exception:
        pass


_SET_HANDLERS = {
    "driftwm": apply_driftwm,
    "hyprland": apply_hyprland,
    "sway": apply_sway,
    "niri": apply_niri,
    "mango": apply_mango,
    "umbriel": apply_umbriel,
}

_LAYOUT_HANDLERS = {
    "driftwm": apply_layout_driftwm,
    "hyprland": apply_layout_hyprland,
    "sway": apply_layout_sway,
    "niri": apply_layout_niri,
    "mango": apply_layout_mango,
    "umbriel": apply_layout_umbriel,
}

_POWER_HANDLERS = {
    "driftwm": apply_power_driftwm,
    "hyprland": apply_power_hyprland,
    "sway": apply_power_sway,
    "niri": apply_power_niri,
    "mango": apply_power_mango,
    "umbriel": apply_power_umbriel,
}


def main():
    parser = argparse.ArgumentParser(description="Serpantinum Monitor Manager")
    subparsers = parser.add_subparsers(dest="action", required=True)

    set_parser = subparsers.add_parser("set", help="Set and persist monitor configuration")
    set_parser.add_argument("--name", required=True, help="Output name, e.g. eDP-1")
    set_parser.add_argument("--resolution", help="Resolution WxH, e.g. 1920x1080")
    set_parser.add_argument("--framerate", help="Refresh rate in Hz, e.g. 60")
    set_parser.add_argument("--scale", type=float, help="Scale factor, e.g. 1.0")
    set_parser.add_argument("--x", type=int, help="Logical X position, e.g. 0")
    set_parser.add_argument("--y", type=int, help="Logical Y position, e.g. 0")
    set_parser.add_argument("--compositor", help="Override target compositor")

    layout_parser = subparsers.add_parser("set-layout", help="Apply and persist 2D positions for multiple monitors")
    layout_parser.add_argument("--layout", required=True, help="JSON array of {name, x, y, ...}")
    layout_parser.add_argument("--compositor", help="Override target compositor")

    power_parser = subparsers.add_parser("set-power", help="Enable or disable a monitor output cleanly")
    power_parser.add_argument("--name", required=True, help="Output name, e.g. HDMI-A-1")
    power_parser.add_argument("--enabled", required=True, help="1/true to enable, 0/false to disable")
    power_parser.add_argument("--resolution", help="Saved resolution WxH")
    power_parser.add_argument("--framerate", help="Saved refresh rate in Hz")
    power_parser.add_argument("--scale", type=float, help="Saved scale factor")
    power_parser.add_argument("--x", type=int, help="Saved logical X position")
    power_parser.add_argument("--y", type=int, help="Saved logical Y position")
    power_parser.add_argument("--compositor", help="Override target compositor")

    args = parser.parse_args()
    env = _resolve_env()
    comp = (args.compositor or detect_compositor(env)).lower()

    if args.action == "set":
        update_serpantinum_settings_batch([{
            "name": args.name,
            "resolution": args.resolution,
            "framerate": args.framerate,
            "scale": args.scale,
            "x": args.x,
            "y": args.y,
        }])
        handler = _SET_HANDLERS.get(comp, apply_generic)
        handler(args.name, args.resolution, args.framerate, args.scale, env, x=args.x, y=args.y)
        print(json.dumps({"success": True, "compositor": comp, "output": args.name}))
        return

    if args.action == "set-layout":
        items = json.loads(args.layout)
        if not isinstance(items, list) or not items:
            sys.stderr.write("Error: --layout must be a non-empty JSON array\n")
            sys.exit(1)
        clean_items = []
        for item in items:
            if not isinstance(item, dict) or not item.get("name"):
                continue
            clean_items.append({
                "name": str(item["name"]),
                "x": int(round(item.get("x", 0) or 0)),
                "y": int(round(item.get("y", 0) or 0)),
                "resolution": item.get("resolution"),
                "framerate": item.get("framerate"),
                "scale": item.get("scale"),
            })
        update_serpantinum_settings_batch(clean_items)
        live_map = _live_monitors_map(env)
        handler = _LAYOUT_HANDLERS.get(comp, apply_layout_generic)
        handler(clean_items, env, live_map)
        print(json.dumps({"success": True, "compositor": comp, "outputs": [i["name"] for i in clean_items]}))
        return

    if args.action == "set-power":
        raw_en = str(args.enabled).strip().lower()
        enabled = raw_en in ("1", "true", "yes", "on", "enable", "enabled")
        live_map = _live_monitors_map(env)
        active_names = [n for n, m in live_map.items() if m.get("active", True)]
        if not enabled and args.name in active_names and len(active_names) <= 1:
            print(json.dumps({"success": False, "compositor": comp, "output": args.name, "error": "Cannot disable the last active monitor"}))
            sys.exit(1)

        live_m = live_map.get(args.name, {})
        res = args.resolution or live_m.get("dimensions")
        rate = args.framerate or live_m.get("framerate")
        sc = _normalize_scale(args.scale if args.scale is not None else live_m.get("scale", 1.0))
        pos = (int(args.x), int(args.y)) if (args.x is not None and args.y is not None) else (
            (int(live_m.get("x", 0)), int(live_m.get("y", 0))) if live_m else None
        )
        update_serpantinum_settings_batch([{
            "name": args.name,
            "resolution": res,
            "framerate": rate,
            "scale": sc,
            "x": pos[0] if pos else None,
            "y": pos[1] if pos else None,
            "powerEnabled": enabled,
        }])
        handler = _POWER_HANDLERS.get(comp, apply_power_generic)
        handler(args.name, enabled, res, rate, sc, pos, env)
        print(json.dumps({"success": True, "compositor": comp, "output": args.name, "enabled": enabled}))


if __name__ == "__main__":
    main()
