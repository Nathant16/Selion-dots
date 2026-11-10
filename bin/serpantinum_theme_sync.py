#!/usr/bin/env python3
import json
import os
import sys

def hex_to_rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(
        max(0, min(255, int(round(rgb[0])))),
        max(0, min(255, int(round(rgb[1])))),
        max(0, min(255, int(round(rgb[2]))))
    )

def interpolate(c1, c2, factor):
    return tuple(c1[i] + (c2[i] - c1[i]) * factor for i in range(3))

def generate_gradient(stops, n=7):
    cleaned_stops = []
    for s in stops:
        if s and isinstance(s, str) and s.startswith("#"):
            if not cleaned_stops or cleaned_stops[-1].lower() != s.lower():
                cleaned_stops.append(s)
    if len(cleaned_stops) < 2:
        return [cleaned_stops[0]] * n if cleaned_stops else ["#e0c56d"] * n

    rgbs = [hex_to_rgb(s) for s in cleaned_stops]
    result = []
    num_segments = len(rgbs) - 1
    for step in range(n):
        t = step / (n - 1)
        seg = min(int(t * num_segments), num_segments - 1)
        seg_t = (t - (seg / num_segments)) * num_segments
        c = interpolate(rgbs[seg], rgbs[seg + 1], seg_t)
        result.append(rgb_to_hex(c))
    return result

def main():
    settings_path = os.path.expanduser("~/.config/serpantinum/settings.json")
    qs_path = os.path.expanduser("~/.local/state/serpantinum/qs_colors.json")

    settings = {}
    if os.path.exists(settings_path):
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                settings = json.load(f)
        except Exception:
            pass

    theme_cfg = settings.get("theme", {})
    is_matugen = theme_cfg.get("matugen", True)
    preset_colors = theme_cfg.get("colors", {})

    qs_colors = {}
    if os.path.exists(qs_path):
        try:
            with open(qs_path, "r", encoding="utf-8") as f:
                qs_colors = json.load(f)
        except Exception:
            pass

    # Determine active palette
    if is_matugen and qs_colors:
        c = qs_colors
    elif preset_colors:
        c = preset_colors
    elif qs_colors:
        c = qs_colors
    else:
        c = {}

    def get_color(key, default):
        val = c.get(key, default)
        if isinstance(val, str):
            return val.lstrip("#")
        return default.lstrip("#")

    frame = get_color("blue", "e0c56d")
    user = get_color("peach", "abcfb0")
    dim = get_color("subtext1", "979080")
    err = get_color("red", "ffb4ab")
    text = get_color("text", "e9e2d4")
    surface = get_color("surface1", "4f462a")
    green = get_color("green", "d3c6a1")

    # If --fish-vars requested:
    if "--fish-vars" in sys.argv:
        print(f"{frame} {user} {dim} {err} {text} {surface}")

    c_top = "#" + user     # Tertiary / Peach
    c_mid = "#" + green    # Secondary / Green
    c_bot = "#" + frame    # Primary / Blue

    # For presets, check if other accent stops exist between top and bottom
    if not is_matugen:
        preset_stops = []
        for k in ["pink", "peach", "yellow", "green", "teal", "sapphire", "blue", "mauve"]:
            v = c.get(k)
            if v and isinstance(v, str) and v.startswith("#"):
                # Avoid very dark background colors in gradient
                r, g, b_val = hex_to_rgb(v)
                lum = (0.299 * r + 0.587 * g + 0.114 * b_val)
                if lum > 40:
                    preset_stops.append(v)
        if len(preset_stops) >= 2:
            gradient_stops = preset_stops
        else:
            gradient_stops = [c_top, c_mid, c_bot]
    else:
        gradient_stops = [c_top, c_mid, c_bot]

    # Generate 7 smooth gradient colors (one per layer/line of the ASCII Arch logo)
    gradient_colors = generate_gradient(gradient_stops, 7)
    logo_colors = {str(i): gradient_colors[i - 1] for i in range(1, 8)}

    # Generate/update ~/.config/fastfetch/config.jsonc
    ff_dir = os.path.expanduser("~/.config/fastfetch")
    os.makedirs(ff_dir, exist_ok=True)
    ff_path = os.path.join(ff_dir, "config.jsonc")

    c_title = "#" + user
    c_keys = "#" + frame
    c_dim = "#" + dim

    logo_source = (
        "$1       /\\\n"
        "$2      /  \\\n"
        "$3     /\\   \\\n"
        "$4    /      \\\n"
        "$5   /   ,,   \\\n"
        "$6  /   |  |  -\\\n"
        "$7 /_-''    ''-_\\"
    )

    ff_cfg = {
        "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
        "logo": {
            "type": "data",
            "source": logo_source,
            "color": logo_colors,
            "padding": {
                "right": 3,
                "top": 1
            }
        },
        "display": {
            "separator": ": ",
            "key": {
                "type": "string",
                "width": 0
            },
            "color": {
                "keys": c_keys,
                "title": c_title,
                "output": c_dim,
                "separator": c_keys
            }
        },
        "modules": [
            {
                "type": "title",
                "color": {
                    "user": c_title,
                    "at": c_dim,
                    "host": c_title
                }
            },
            {
                "type": "separator",
                "string": "─",
                "outputColor": c_dim
            },
            "os",
            "kernel",
            "uptime",
            "packages",
            "shell",
            {
                "type": "wm",
                "key": "WM"
            },
            "terminal"
        ]
    }

    try:
        with open(ff_path, "w", encoding="utf-8") as f:
            json.dump(ff_cfg, f, indent=2)
    except Exception:
        pass

if __name__ == "__main__":
    main()
