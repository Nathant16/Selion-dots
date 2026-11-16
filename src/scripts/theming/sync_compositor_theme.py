#!/usr/bin/env python3
"""
Synchronizes window border colors, corner rounding, window opacity (kitty, ski),
and blur across all 5 Window Managers (Hyprland, Sway, Niri, Mango, DriftWM)
and native apps adaptively and immediately to match the active theme.
"""

import sys
import os
import re
import json
import shutil
import subprocess
from pathlib import Path

DEFAULT_ROUNDING = 12

def ensure_environment():
    try:
        uid = os.getuid()
        runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{uid}"))
        if not runtime_dir.is_dir():
            return

        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            hypr_dir = runtime_dir / "hypr"
            if hypr_dir.is_dir():
                instances = [p.name for p in hypr_dir.iterdir() if p.is_dir()]
                if instances:
                    os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = sorted(instances)[-1]

        if not os.environ.get("SWAYSOCK"):
            sway_socks = list(runtime_dir.glob("sway-ipc.*.sock"))
            if sway_socks:
                os.environ["SWAYSOCK"] = str(sway_socks[0])

        if not os.environ.get("NIRI_SOCKET"):
            niri_socks = list(runtime_dir.glob("niri*.sock"))
            if niri_socks:
                os.environ["NIRI_SOCKET"] = str(niri_socks[0])

        if not os.environ.get("DRIFTWM_SOCKET"):
            drift_dir = runtime_dir / "driftwm"
            if drift_dir.is_dir():
                drift_socks = list(drift_dir.glob("ipc-*.sock"))
                if drift_socks:
                    os.environ["DRIFTWM_SOCKET"] = str(drift_socks[0])

        if not os.environ.get("WAYLAND_DISPLAY"):
            wl_socks = sorted([p.name for p in runtime_dir.glob("wayland-[0-9]*") if not p.name.endswith(".lock") and not p.name.endswith(".sock")])
            if wl_socks:
                os.environ["WAYLAND_DISPLAY"] = wl_socks[0]
    except Exception:
        pass

DEFAULT_COLORS = {
    "base": "1e1e2e",
    "surface0": "313244",
    "surface1": "45475a",
    "text": "cdd6f4",
    "subtext0": "a6adc8",
    "blue": "89b4fa",
    "mauve": "cba6f7",
    "sapphire": "74c7ec",
    "red": "f38ba8"
}

def clean_hex(val, fallback="cba6f7"):
    if not val:
        return fallback
    if isinstance(val, dict):
        val = val.get("hex") or val.get("color") or val.get("default", {}).get("hex") or fallback
    val = str(val).strip().lstrip("#")
    if len(val) == 6:
        return val
    elif len(val) == 8:
        return val[:6]
    elif len(val) == 3:
        return "".join(c * 2 for c in val)
    return fallback

def load_active_colors(state_dir):
    colors = dict(DEFAULT_COLORS)
    candidates = [
        state_dir / "qs_colors.json",
        state_dir / "qs_matugen_colors.json",
        state_dir / "matugen" / "palette.json"
    ]
    for c_path in candidates:
        if c_path.is_file():
            try:
                with open(c_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                c_map = data.get("colors") if isinstance(data, dict) and "colors" in data else data
                if isinstance(c_map, dict):
                    for k in colors.keys():
                        if k in c_map:
                            colors[k] = clean_hex(c_map[k], colors[k])
                    return colors
            except Exception:
                continue
    return colors

def get_settings():
    settings_path = Path.home() / ".config" / "serpantinum" / "settings.json"
    if settings_path.is_file():
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def get_rounding(settings):
    th = settings.get("theme", {})
    if "windowRounding" in th:
        try:
            return int(th["windowRounding"])
        except Exception:
            pass
    return DEFAULT_ROUNDING

def get_element_opacity(settings):
    th = settings.get("theme", {})
    if "elementOpacity" in th:
        try:
            return int(th["elementOpacity"])
        except Exception:
            pass
    return 100

def get_blur_background(settings):
    th = settings.get("theme", {})
    if "blurBackground" in th:
        return bool(th["blurBackground"])
    return True

def get_apply_effects_to_windows(settings):
    th = settings.get("theme", {})
    if "applyEffectsToWindows" in th:
        return bool(th["applyEffectsToWindows"])
    return True

def get_app_opacity(element_opacity, apply_to_windows=True):
    if not apply_to_windows or element_opacity >= 99:
        return 1.0
    val = round((200.0 + float(element_opacity)) / 300.0, 2)
    return max(0.50, min(1.0, val))

def get_ski_opacity(element_opacity, apply_to_windows=True):
    if not apply_to_windows or element_opacity >= 99:
        return 100
    val = int(round((200.0 + float(element_opacity)) / 3.0))
    return max(50, min(100, val))

def sync_apps(app_opacity, ski_opacity, blur_background, apply_to_windows):
    # 1. Kitty configuration
    # Compositors (DriftWM, Hyprland, Sway, Niri) apply window-level opacity rules.
    # Setting background_opacity to app_opacity causes double multiplication
    # (opacity^2), making kitty far more transparent than other windows (like ski).
    # Keep background_opacity at 1.0 so compositor opacity is uniform across all windows.
    kitty_cfg = Path.home() / ".config" / "kitty" / "kitty.conf"
    if kitty_cfg.is_file():
        try:
            with open(kitty_cfg, "r", encoding="utf-8") as f:
                content = f.read()

            if re.search(r'^\s*background_opacity\s+.*$', content, re.MULTILINE):
                content = re.sub(r'^\s*background_opacity\s+.*$', 'background_opacity 1.0', content, flags=re.MULTILINE)
            else:
                content = content.rstrip() + '\nbackground_opacity 1.0\n'

            blur_val = 1 if (blur_background and apply_to_windows) else 0
            if re.search(r'^\s*background_blur\s+.*$', content, re.MULTILINE):
                content = re.sub(r'^\s*background_blur\s+.*$', f'background_blur {blur_val}', content, flags=re.MULTILINE)
            else:
                content = content.rstrip() + f'\nbackground_blur {blur_val}\n'

            with open(kitty_cfg, "w", encoding="utf-8") as f:
                f.write(content)

            # Signal kitty to reload config
            subprocess.run(["pkill", "-USR1", "-x", "kitty"], capture_output=True)
        except Exception:
            pass

    # 2. Ski file manager configuration
    ski_cfg = Path.home() / ".config" / "ski" / "settings.json"
    if ski_cfg.is_file():
        try:
            with open(ski_cfg, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                data["opacity"] = ski_opacity
                with open(ski_cfg, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2)
        except Exception:
            pass

def write_hyprland_theme(state_dir, colors, rounding, app_opacity, blur_background, apply_to_windows):
    active = f"rgba({colors['mauve']}ee)"
    inactive = f"rgba({colors['surface0']}aa)"

    content = f"""-- Auto-generated by Serpantinum Theme Synchronizer
return {{
    active_border = "{active}",
    inactive_border = "{inactive}",
    rounding = {rounding},
    blur_enabled = {"true" if blur_background else "false"},
}}
"""
    theme_file = state_dir / "theme_hyprland.lua"
    with open(theme_file, "w", encoding="utf-8") as f:
        f.write(content)

    no_blur_line = "    no_blur = true,\n" if not (blur_background and apply_to_windows) else ""

    rules_content = f"""-- Auto-generated by Serpantinum Theme Synchronizer
hl.window_rule({{
    name = "serpantinum-kitty-opacity",
    opacity = "{app_opacity} {app_opacity}",
{no_blur_line}    match = {{ class = "kitty" }},
}})
hl.window_rule({{
    name = "serpantinum-ski-opacity",
    opacity = "{app_opacity} {app_opacity}",
{no_blur_line}    match = {{ class = "^(ski|ski-file-manager)$" }},
}})
"""
    rules_file = state_dir / "theme_hyprland_rules.lua"
    with open(rules_file, "w", encoding="utf-8") as f:
        f.write(rules_content)

    # Live reload Hyprland if running
    is_running = False
    try:
        proc = subprocess.run(["pgrep", "-x", "Hyprland"], capture_output=True, text=True)
        is_running = proc.returncode == 0
    except Exception:
        pass

    if is_running or os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        eval_cmd = (
            f'hl.config({{ '
            f'general = {{ '
            f'["col.active_border"] = "{active}", '
            f'["col.inactive_border"] = "{inactive}" '
            f'}}, '
            f'decoration = {{ rounding = {rounding}, blur = {{ enabled = {"true" if blur_background else "false"} }} }} '
            f'}})'
        )
        try:
            subprocess.run(["hyprctl", "eval", eval_cmd], capture_output=True, timeout=2)
            subprocess.run(["hyprctl", "eval", 'hl.animation({ leaf = "borderangle", enabled = false })'], capture_output=True, timeout=2)
            subprocess.run(["hyprctl", "keyword", "decoration:blur:enabled", "1" if blur_background else "0"], capture_output=True, timeout=2)
            subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=2)
        except Exception:
            pass

def is_swayfx():
    try:
        proc = subprocess.run(["sway", "-v"], capture_output=True, text=True)
        return "swayfx" in proc.stdout.lower()
    except Exception:
        return False

def write_sway_theme(state_dir, colors, rounding, app_opacity, blur_background):
    fx_rounding = f"\ncorner_radius {rounding}" if is_swayfx() else ""
    fx_blur = f"\nblur {'enable' if blur_background else 'disable'}\nblur_passes 3\nblur_radius 5" if is_swayfx() else ""
    content = f"""# Auto-generated by Serpantinum Theme Synchronizer
default_border pixel 2
default_floating_border pixel 2
client.focused #{colors['mauve']} #{colors['base']} #{colors['text']} #{colors['mauve']} #{colors['mauve']}
client.focused_inactive #{colors['surface0']} #{colors['base']} #{colors['subtext0']} #{colors['surface0']} #{colors['surface0']}
client.unfocused #{colors['surface0']} #{colors['base']} #{colors['subtext0']} #{colors['surface0']} #{colors['surface0']}
client.urgent #{colors['red']} #{colors['base']} #{colors['text']} #{colors['red']} #{colors['red']}{fx_rounding}{fx_blur}

for_window [app_id="kitty"] opacity {app_opacity}
for_window [app_id="ski"] opacity {app_opacity}
for_window [app_id="ski-file-manager"] opacity {app_opacity}
"""
    theme_file = state_dir / "theme_sway"
    with open(theme_file, "w", encoding="utf-8") as f:
        f.write(content)

    is_running = False
    try:
        proc = subprocess.run(["pgrep", "-x", "sway"], capture_output=True, text=True)
        is_running = proc.returncode == 0
    except Exception:
        pass

    if is_running or os.environ.get("SWAYSOCK"):
        try:
            cmd = (
                f"client.focused #{colors['mauve']} #{colors['base']} #{colors['text']} #{colors['mauve']} #{colors['mauve']}; "
                f"client.focused_inactive #{colors['surface0']} #{colors['base']} #{colors['subtext0']} #{colors['surface0']} #{colors['surface0']}; "
                f"client.unfocused #{colors['surface0']} #{colors['base']} #{colors['subtext0']} #{colors['surface0']} #{colors['surface0']}; "
                f"[app_id=\"kitty\"] opacity {app_opacity}; "
                f"[app_id=\"ski\"] opacity {app_opacity}; "
                f"[app_id=\"ski-file-manager\"] opacity {app_opacity}; "
                f"for_window [app_id=\"kitty\"] opacity {app_opacity}; "
                f"for_window [app_id=\"ski\"] opacity {app_opacity}; "
                f"for_window [app_id=\"ski-file-manager\"] opacity {app_opacity}"
            )
            if is_swayfx():
                cmd += f"; corner_radius {rounding}; blur {'enable' if blur_background else 'disable'}"
            subprocess.run(["swaymsg", cmd], capture_output=True, timeout=2)
        except Exception:
            pass

def write_niri_theme(state_dir, colors, rounding, app_opacity, blur_background):
    content = f"""// Auto-generated by Serpantinum Theme Synchronizer
layout {{
    focus-ring {{
        width 2
        active-color "#{colors['mauve']}"
        inactive-color "#{colors['surface0']}"
    }}
    border {{
        off
    }}
}}

window-rule {{
    geometry-corner-radius {rounding}
    clip-to-geometry true
}}

window-rule {{
    match app-id="kitty"
    match app-id="ski"
    match app-id="ski-file-manager"
    opacity {app_opacity}
}}
"""
    theme_file = state_dir / "theme_niri.kdl"
    with open(theme_file, "w", encoding="utf-8") as f:
        f.write(content)

    is_running = False
    try:
        proc = subprocess.run(["pgrep", "-x", "niri"], capture_output=True, text=True)
        is_running = proc.returncode == 0
    except Exception:
        pass

    if is_running or os.environ.get("NIRI_SOCKET"):
        try:
            subprocess.run(["niri", "msg", "action", "load-config-file"], capture_output=True, timeout=2)
        except Exception:
            pass
        niri_cfg = Path.home() / ".config" / "niri" / "config.kdl"
        if niri_cfg.is_file():
            try:
                niri_cfg.touch()
            except Exception:
                pass

def write_mango_theme(state_dir, colors, rounding, app_opacity, blur_background, apply_to_windows):
    blur_layer = 1 if blur_background else 0
    blur_passes = 2 if blur_background else 0
    blur_radius = 5 if blur_background else 0

    no_blur = ",noblur:1" if not (blur_background and apply_to_windows) else ""

    content = f"""# Auto-generated by Serpantinum Theme Synchronizer
border_px=2
border_radius={rounding}
focus_color=0x{colors['mauve']}ff
border_color=0x{colors['surface0']}ff
urgent_color=0x{colors['red']}ff
root_color=0x{colors['base']}ff
shadows_color=0x00000055
blur_layer={blur_layer}
blur_params_num_passes={blur_passes}
blur_params_radius={blur_radius}

window_rule=focused_opacity:{app_opacity},unfocused_opacity:{app_opacity}{no_blur},app_id:kitty
window_rule=focused_opacity:{app_opacity},unfocused_opacity:{app_opacity}{no_blur},app_id:ski
window_rule=focused_opacity:{app_opacity},unfocused_opacity:{app_opacity}{no_blur},app_id:ski-file-manager
"""
    theme_file = state_dir / "theme_mango.conf"
    with open(theme_file, "w", encoding="utf-8") as f:
        f.write(content)

    for cfg_name in ["config.conf", "default/appearance.conf"]:
        mango_cfg = Path.home() / ".config" / "mango" / cfg_name
        if mango_cfg.is_file():
            try:
                mango_cfg.touch()
            except Exception:
                pass

def write_driftwm_theme(state_dir, colors, rounding, app_opacity, blur_background, apply_to_windows):
    should_blur_windows = blur_background and apply_to_windows

    effects_block = f"""[effects]
blur_radius = {5 if blur_background else 0}
blur_strength = {1.5 if blur_background else 0.0}
animate_blur_fps = {20 if blur_background else 0}
"""

    decorations_block = f"""[decorations]
corner_radius = {rounding}
shadow = true
default_mode = "minimal"
border_width = 2
border_color = "#{colors['surface0']}"
border_color_focused = "#{colors['mauve']}"
opacity = 1.0
opacity_focused = 1.0
blur = {"true" if should_blur_windows else "false"}
"""

    theme_file = state_dir / "theme_driftwm.toml"
    with open(theme_file, "w", encoding="utf-8") as f:
        f.write(effects_block + "\n" + decorations_block + "\n")

    # Update ~/.config/driftwm/config.toml
    config_file = Path.home() / ".config" / "driftwm" / "config.toml"
    if config_file.is_file():
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                text = f.read()

            lines = text.splitlines()
            new_lines = []
            i = 0
            effects_found = False
            decorations_found = False

            while i < len(lines):
                line = lines[i]
                stripped = line.strip()

                if stripped == "[decorations]":
                    decorations_found = True
                    new_lines.extend(decorations_block.strip().splitlines())
                    i += 1
                    while i < len(lines) and not lines[i].strip().startswith("["):
                        i += 1
                    continue

                if stripped == "[effects]":
                    effects_found = True
                    new_lines.extend(effects_block.strip().splitlines())
                    i += 1
                    while i < len(lines) and not lines[i].strip().startswith("["):
                        i += 1
                    continue

                new_lines.append(line)
                i += 1

            if not effects_found:
                dec_idx = -1
                for idx, l in enumerate(new_lines):
                    if l.strip() == "[decorations]":
                        dec_idx = idx
                        break
                if dec_idx != -1:
                    new_lines[dec_idx:dec_idx] = [""] + effects_block.strip().splitlines() + [""]
                else:
                    new_lines.extend([""] + effects_block.strip().splitlines())

            result_text = "\n".join(new_lines) + "\n"
            target_apps = ["kitty", "ski", "ski-file-manager"]

            for app in target_apps:
                pattern = rf'(\[\[window_rules\]\](?:(?!\n\[|# █).)*?app_id\s*=\s*"{app}"(?:(?!\n\[|# █).)*)'
                match = re.search(pattern, result_text, re.DOTALL)
                if match:
                    rule_content = match.group(1)
                    if re.search(r'\bopacity\s*=', rule_content):
                        new_rule = re.sub(r'opacity\s*=\s*[0-9.]+', f'opacity = {app_opacity}', rule_content)
                    else:
                        new_rule = rule_content.rstrip() + f'\nopacity = {app_opacity}\n'
                    if re.search(r'\bblur\s*=', new_rule):
                        new_rule = re.sub(r'blur\s*=\s*(?:true|false)', f'blur = {"true" if should_blur_windows else "false"}', new_rule)
                    else:
                        new_rule = new_rule.rstrip() + f'\nblur = {"true" if should_blur_windows else "false"}\n'
                    result_text = result_text[:match.start()] + new_rule + result_text[match.end():]
                else:
                    kb_match = re.search(r'\n\[keybindings\]', result_text)
                    rule_str = f'\n[[window_rules]]\napp_id = "{app}"\nopacity = {app_opacity}\nblur = {"true" if should_blur_windows else "false"}\n'
                    if kb_match:
                        pos = kb_match.start()
                        result_text = result_text[:pos] + rule_str + result_text[pos:]
                    else:
                        result_text += rule_str

            with open(config_file, "w", encoding="utf-8") as f:
                f.write(result_text)
        except Exception:
            pass

    is_running = False
    try:
        proc = subprocess.run(["pgrep", "-x", "driftwm"], capture_output=True, text=True)
        is_running = proc.returncode == 0
    except Exception:
        pass

    if is_running:
        try:
            env = dict(os.environ)
            if not env.get("WAYLAND_DISPLAY"):
                runtime_dir = Path(env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
                for sock in runtime_dir.glob("wayland-*"):
                    if not sock.name.endswith(".lock"):
                        env["WAYLAND_DISPLAY"] = sock.name
                        break
            subprocess.run(["driftwm", "msg", "action", "reload-config"], env=env, capture_output=True, timeout=2)

            # Live update existing windows immediately
            state_proc = subprocess.run(["driftwm", "msg", "state", "--json"], env=env, capture_output=True, text=True, timeout=2)
            if state_proc.returncode == 0 and state_proc.stdout:
                try:
                    data = json.loads(state_proc.stdout)
                    st = data.get("State") or data.get("Ok", {}).get("State", {}) or {}
                    for w in st.get("windows", []):
                        app_id = w.get("app_id", "")
                        w_id = w.get("id")
                        if app_id in ["kitty", "ski", "ski-file-manager"] and w_id is not None:
                            subprocess.run(["driftwm", "msg", "opacity", "--id", str(w_id), str(app_opacity)], env=env, capture_output=True, timeout=1)
                except Exception:
                    pass
        except Exception:
            pass

def sync_cursor():
    try:
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", "Windows-11M-Dark"], capture_output=True, timeout=1)
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", "28"], capture_output=True, timeout=1)
    except Exception:
        pass
    try:
        subprocess.run(["hyprctl", "setcursor", "Windows-11M-Dark", "28"], capture_output=True, timeout=1)
    except Exception:
        pass
    try:
        subprocess.run(["swaymsg", "seat", "seat0", "xcursor_theme", "Windows-11M-Dark", "28"], capture_output=True, timeout=1)
    except Exception:
        pass

def main():
    ensure_environment()
    sync_cursor()
    state_dir = Path.home() / ".local" / "state" / "serpantinum"
    state_dir.mkdir(parents=True, exist_ok=True)

    colors = load_active_colors(state_dir)

    # Allow custom CLI colors json
    if len(sys.argv) > 1 and sys.argv[1].startswith("{"):
        try:
            custom = json.loads(sys.argv[1])
            c_map = custom.get("colors") if "colors" in custom else custom
            for k in colors.keys():
                if k in c_map:
                    colors[k] = clean_hex(c_map[k], colors[k])
        except Exception:
            pass

    settings = get_settings()
    rounding = get_rounding(settings)
    element_opacity = get_element_opacity(settings)
    blur_background = get_blur_background(settings)
    apply_to_windows = get_apply_effects_to_windows(settings)
    app_opacity = get_app_opacity(element_opacity, apply_to_windows)
    ski_opacity = get_ski_opacity(element_opacity, apply_to_windows)

    sync_apps(app_opacity, ski_opacity, blur_background, apply_to_windows)
    write_hyprland_theme(state_dir, colors, rounding, app_opacity, blur_background, apply_to_windows)
    write_sway_theme(state_dir, colors, rounding, app_opacity, blur_background)
    write_niri_theme(state_dir, colors, rounding, app_opacity, blur_background)
    write_mango_theme(state_dir, colors, rounding, app_opacity, blur_background, apply_to_windows)
    write_driftwm_theme(state_dir, colors, rounding, app_opacity, blur_background, apply_to_windows)

if __name__ == "__main__":
    main()
