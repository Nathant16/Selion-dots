#!/usr/bin/env python3
import glob
import json
import os
import subprocess


_KNOWN_COMPOSITORS = ("driftwm", "hyprland", "sway", "niri", "mango", "umbriel")


def get_running_compositors():
    """Return lowercase names of known Wayland compositors currently running for this UID."""
    found = set()
    try:
        proc = subprocess.run(
            ["ps", "-u", str(os.getuid()), "-o", "comm="],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                comm = line.strip().lower()
                if comm in _KNOWN_COMPOSITORS:
                    found.add(comm)
    except Exception:
        pass
    return found


def get_wayland_env():
    env = dict(os.environ)
    if not env.get("XDG_RUNTIME_DIR"):
        env["XDG_RUNTIME_DIR"] = f"/run/user/{os.getuid()}"
    runtime_dir = env["XDG_RUNTIME_DIR"]
    running = get_running_compositors()

    def _alive(comp):
        return (not running) or (comp in running)

    if not _alive("hyprland"):
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    if not _alive("sway"):
        env.pop("SWAYSOCK", None)
    if not _alive("niri"):
        env.pop("NIRI_SOCKET", None)
    if not _alive("umbriel"):
        env.pop("UMBRIEL_SOCKET", None)

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

    if _alive("hyprland") and not env.get("HYPRLAND_INSTANCE_SIGNATURE") and os.path.exists(f"{runtime_dir}/hypr"):
        socks = glob.glob(f"{runtime_dir}/hypr/*/.socket.sock")
        if socks:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = os.path.basename(os.path.dirname(max(socks, key=os.path.getmtime)))

    if _alive("sway") and not env.get("SWAYSOCK"):
        sw_socks = glob.glob(f"{runtime_dir}/sway-ipc.*.sock")
        if sw_socks:
            env["SWAYSOCK"] = max(sw_socks, key=os.path.getmtime)

    if _alive("niri") and not env.get("NIRI_SOCKET"):
        niri_socks = glob.glob(f"{runtime_dir}/niri.*.sock")
        if niri_socks:
            env["NIRI_SOCKET"] = max(niri_socks, key=os.path.getmtime)

    if _alive("umbriel") and not env.get("UMBRIEL_SOCKET"):
        umb_socks = glob.glob(f"{runtime_dir}/umbriel*.sock")
        if umb_socks:
            env["UMBRIEL_SOCKET"] = max(umb_socks, key=os.path.getmtime)

    return env


def _norm_transform(val):
    if val is None:
        return "normal"
    if isinstance(val, int):
        mapping = {
            0: "normal",
            1: "90",
            2: "180",
            3: "270",
            4: "flipped",
            5: "flipped-90",
            6: "flipped-180",
            7: "flipped-270",
        }
        return mapping.get(val, "normal")
    s = str(val).strip().lower().lstrip("_")
    s = s.replace("flipped90", "flipped-90").replace("flipped180", "flipped-180").replace("flipped270", "flipped-270")
    return s if s else "normal"


def _make_entry(name, res_list, res_rates_map, cur_res, rate_int, scale, active, x=0, y=0, transform="normal"):
    if cur_res not in res_list:
        res_list.insert(0, cur_res)
    cur_framerates = res_rates_map.get(cur_res, [str(rate_int)])
    if not cur_framerates:
        cur_framerates = [str(rate_int)]
    return {
        "name": name,
        "dimensions": cur_res,
        "framerate": str(rate_int),
        "framerates": cur_framerates,
        "resolutions_map": res_rates_map,
        "scale": scale,
        "active": active,
        "x": int(round(x)) if x is not None else 0,
        "y": int(round(y)) if y is not None else 0,
        "transform": _norm_transform(transform),
        "modes": res_list,
    }


def _collect_mode_table(modes, width_key="width", height_key="height", rate_fn=None):
    res_rates_map = {}
    res_list = []
    seen = set()
    for m in modes or []:
        mw = m.get(width_key)
        mh = m.get(height_key)
        if not mw or not mh:
            continue
        s = f"{int(mw)}x{int(mh)}"
        if s not in seen:
            seen.add(s)
            res_list.append(s)
        r_str = str(rate_fn(m)) if rate_fn else str(int(round(float(m.get("refresh", 60.0) or 60.0))))
        res_rates_map.setdefault(s, [])
        if r_str not in res_rates_map[s]:
            res_rates_map[s].append(r_str)
    for s in res_rates_map:
        res_rates_map[s].sort(key=lambda r: int(r), reverse=True)
    return res_list, res_rates_map


def get_drm_modes():
    modes_map = {}
    for p in glob.glob("/sys/class/drm/card*-*/modes"):
        parts = os.path.basename(os.path.dirname(p)).split("-", 1)
        conn = parts[1] if len(parts) > 1 else parts[0]
        try:
            status_p = os.path.join(os.path.dirname(p), "status")
            if os.path.exists(status_p):
                with open(status_p, "r", encoding="utf-8") as sf:
                    if sf.read().strip() != "connected":
                        continue
        except Exception:
            pass
        try:
            with open(p, "r", encoding="utf-8") as f:
                modes = [line.strip() for line in f if line.strip()]
            seen = set()
            dedup = []
            for m in modes:
                if m not in seen:
                    seen.add(m)
                    dedup.append(m)
            if dedup:
                modes_map[conn] = dedup
        except Exception:
            pass
    return modes_map


def get_wlr_randr(env):
    try:
        proc = subprocess.run(["wlr-randr", "--json"], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            return data if isinstance(data, list) else None
    except Exception:
        pass
    return None


def get_hyprland_monitors(env):
    for cmd in (["hyprctl", "monitors", "all", "-j"], ["hyprctl", "monitors", "-j"]):
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=2, env=env)
            if proc.returncode == 0 and proc.stdout.strip():
                data = json.loads(proc.stdout)
                if isinstance(data, list) and data:
                    return data
        except Exception:
            pass
    return None


def get_niri_outputs(env):
    try:
        proc = subprocess.run(["niri", "msg", "--json", "outputs"], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            return data if isinstance(data, dict) else None
    except Exception:
        pass
    return None


def get_sway_outputs(env):
    try:
        proc = subprocess.run(["swaymsg", "-t", "get_outputs", "-r"], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            return data if isinstance(data, list) else None
    except Exception:
        pass
    return None


def get_umbriel_outputs(env):
    try:
        proc = subprocess.run(["umbriel", "outputs", "--json"], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            if isinstance(data, dict):
                data = list(data.values())
            return data if isinstance(data, list) else None
    except Exception:
        pass
    return None


def _build_from_hyprland(hypr_monitors):
    saved_cfg = _saved_monitor_prefs()
    monitors = []
    for out in hypr_monitors:
        name = out.get("name", "eDP-1")
        active = not out.get("disabled", False)
        saved_m = saved_cfg.get(name, {}) if isinstance(saved_cfg.get(name), dict) else {}
        w = int(out.get("width", 1920) or 1920)
        h = int(out.get("height", 1080) or 1080)
        rate = int(round(float(out.get("refreshRate", 60.0) or 60.0)))
        scale = float(out.get("scale", 1.0) or 1.0)
        x = int(out.get("x", 0) or 0)
        y = int(out.get("y", 0) or 0)
        transform = _norm_transform(out.get("transform", 0))
        cur_res = f"{w}x{h}"
        if not active and saved_m.get("resolution"):
            cur_res = str(saved_m["resolution"])
            if saved_m.get("framerate"):
                try:
                    rate = int(round(float(saved_m["framerate"])))
                except (TypeError, ValueError):
                    pass
            if saved_m.get("scale") is not None:
                try:
                    scale = float(saved_m["scale"] or scale)
                except (TypeError, ValueError):
                    pass
            if saved_m.get("x") is not None and saved_m.get("y") is not None:
                x = int(saved_m.get("x", 0) or 0)
                y = int(saved_m.get("y", 0) or 0)

        res_rates_map = {}
        res_list = []
        seen = set()
        for m_str in out.get("availableModes", []) or []:
            try:
                mode_part, hz_part = m_str.split("@", 1)
                mode_part = mode_part.strip()
                r_str = str(int(round(float(hz_part.replace("Hz", "").strip()))))
                if mode_part not in seen:
                    seen.add(mode_part)
                    res_list.append(mode_part)
                res_rates_map.setdefault(mode_part, [])
                if r_str not in res_rates_map[mode_part]:
                    res_rates_map[mode_part].append(r_str)
            except Exception:
                pass
        for s in res_rates_map:
            res_rates_map[s].sort(key=lambda r: int(r), reverse=True)

        monitors.append(_make_entry(name, res_list, res_rates_map, cur_res, rate, scale, active, x, y, transform))
    return monitors


def _saved_monitor_prefs():
    try:
        s_file = os.path.expanduser("~/.config/serpantinum/settings.json")
        if os.path.exists(s_file):
            with open(s_file, "r", encoding="utf-8") as sf:
                data = json.load(sf).get("display", {}).get("monitors", {})
                return data if isinstance(data, dict) else {}
    except Exception:
        pass
    return {}


def _umbriel_disabled_outputs():
    """Return configured disabled outputs from ~/.config/umbriel/config/monitors.toml."""
    import re
    disabled = {}
    toml_path = os.path.expanduser("~/.config/umbriel/config/monitors.toml")
    if not os.path.exists(toml_path):
        return disabled
    try:
        lines = open(toml_path, "r", encoding="utf-8").read().splitlines()
        cur_name = None
        cur_data = {}
        for line in lines:
            st = line.strip()
            m_hdr = re.match(r'^\[output\.(?:"([^"]+)"|([A-Za-z0-9_.-]+))\]\s*$', st)
            if m_hdr:
                if cur_name and cur_data.get("enabled") is False:
                    disabled[cur_name] = cur_data
                cur_name = m_hdr.group(1) or m_hdr.group(2)
                cur_data = {}
                continue
            if st.startswith("["):
                if cur_name and cur_data.get("enabled") is False:
                    disabled[cur_name] = cur_data
                cur_name = None
                cur_data = {}
                continue
            if cur_name:
                if re.match(r'^enabled\s*=\s*false\b', st):
                    cur_data["enabled"] = False
                m_mode = re.match(r'^mode\s*=\s*"([^"]+)"', st)
                if m_mode:
                    cur_data["mode"] = m_mode.group(1)
                m_pos = re.match(r'^position\s*=\s*\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\]', st)
                if m_pos:
                    cur_data["x"] = int(m_pos.group(1))
                    cur_data["y"] = int(m_pos.group(2))
                m_sc = re.match(r'^scale\s*=\s*([0-9.]+)', st)
                if m_sc:
                    cur_data["scale"] = float(m_sc.group(1))
        if cur_name and cur_data.get("enabled") is False:
            disabled[cur_name] = cur_data
    except Exception:
        pass
    return disabled


def _build_from_niri(niri_data):
    saved_cfg = _saved_monitor_prefs()
    monitors = []
    for out_name, out in niri_data.items():
        if not isinstance(out, dict):
            continue
        name = out.get("name") or out_name
        modes = out.get("modes", []) or []
        cur_idx = out.get("current_mode")
        cur_mode = modes[cur_idx] if isinstance(cur_idx, int) and 0 <= cur_idx < len(modes) else (modes[0] if modes else None)

        w = int(cur_mode.get("width", 1920)) if cur_mode else 1920
        h = int(cur_mode.get("height", 1080)) if cur_mode else 1080
        rate = int(round(int(cur_mode.get("refresh_rate", 60000) or 60000) / 1000.0)) if cur_mode else 60
        logical = out.get("logical")
        active = logical is not None
        saved_m = saved_cfg.get(name, {}) if isinstance(saved_cfg.get(name), dict) else {}
        if isinstance(logical, dict):
            x = int(logical.get("x", 0))
            y = int(logical.get("y", 0))
            scale = float(logical.get("scale", 1.0) or 1.0)
            transform = _norm_transform(logical.get("transform"))
        else:
            x = int(saved_m.get("x", 0) or 0)
            y = int(saved_m.get("y", 0) or 0)
            scale = float(saved_m.get("scale", 1.0) or 1.0)
            transform = "normal"

        res_list, res_rates_map = _collect_mode_table(
            modes,
            rate_fn=lambda m: int(round(int(m.get("refresh_rate", 60000) or 60000) / 1000.0)),
        )
        monitors.append(_make_entry(name, res_list, res_rates_map, f"{w}x{h}", rate, scale, active, x, y, transform))
    return monitors


def _build_from_wlr_randr(wlr_data, drm_modes):
    saved_cfg = _saved_monitor_prefs()
    monitors = []
    for out in wlr_data:
        name = out.get("name", "Display")
        cur_mode = next((m for m in out.get("modes", []) if m.get("current")), None)
        if not cur_mode and out.get("modes"):
            cur_mode = next((m for m in out["modes"] if m.get("preferred")), out["modes"][0])

        w = int(cur_mode.get("width", 1920)) if cur_mode else 1920
        h = int(cur_mode.get("height", 1080)) if cur_mode else 1080
        rate = int(round(float(cur_mode.get("refresh", 60.0) or 60.0))) if cur_mode else 60
        scale = float(out.get("scale", 1.0) or 1.0)
        active = out.get("enabled", True) is not False
        pos = out.get("position") or {}
        saved_m = saved_cfg.get(name, {}) if isinstance(saved_cfg.get(name), dict) else {}
        if isinstance(pos, dict) and (active or pos.get("x", 0) != 0 or pos.get("y", 0) != 0):
            x = int(pos.get("x", 0) or 0)
            y = int(pos.get("y", 0) or 0)
        else:
            x = int(saved_m.get("x", 0) or 0)
            y = int(saved_m.get("y", 0) or 0)
        if not active and saved_m.get("scale") is not None:
            try:
                scale = float(saved_m.get("scale", scale) or scale)
            except (TypeError, ValueError):
                pass
        transform = _norm_transform(out.get("transform", "normal"))

        res_list, res_rates_map = _collect_mode_table(out.get("modes", []))
        if not res_list and name in drm_modes:
            res_list = list(drm_modes[name])

        monitors.append(_make_entry(name, res_list, res_rates_map, f"{w}x{h}", rate, scale, active, x, y, transform))
    return monitors


def _build_from_sway(sway_data, drm_modes):
    saved_cfg = _saved_monitor_prefs()
    monitors = []
    for out in sway_data:
        name = out.get("name", "Display")
        modes = out.get("modes", []) or []
        cur_mode = out.get("current_mode")
        if not cur_mode and modes:
            cur_mode = modes[0]
        cur_mode = cur_mode or {}
        w = int(cur_mode.get("width", 1920) or 1920)
        h = int(cur_mode.get("height", 1080) or 1080)
        rate = int(round(int(cur_mode.get("refresh", 60000) or 60000) / 1000.0))
        active = bool(out.get("active", True))
        saved_m = saved_cfg.get(name, {}) if isinstance(saved_cfg.get(name), dict) else {}
        cur_res = f"{w}x{h}"
        if not active and saved_m.get("resolution"):
            cur_res = str(saved_m["resolution"])
            if saved_m.get("framerate"):
                try:
                    rate = int(round(float(saved_m["framerate"])))
                except (TypeError, ValueError):
                    pass
        scale = float(out.get("scale", 1.0) or 1.0)
        rect = out.get("rect") or {}
        if active:
            x = int(rect.get("x", 0) or 0)
            y = int(rect.get("y", 0) or 0)
        else:
            x = int(saved_m.get("x", rect.get("x", 0)) or 0)
            y = int(saved_m.get("y", rect.get("y", 0)) or 0)
            if saved_m.get("scale") is not None:
                try:
                    scale = float(saved_m.get("scale", scale) or scale)
                except (TypeError, ValueError):
                    pass
        transform = _norm_transform(out.get("transform", "normal"))

        res_list, res_rates_map = _collect_mode_table(
            modes,
            rate_fn=lambda m: int(round(int(m.get("refresh", 60000) or 60000) / 1000.0)),
        )
        if not res_list and name in drm_modes:
            res_list = list(drm_modes[name])

        monitors.append(_make_entry(name, res_list, res_rates_map, cur_res, rate, scale, active, x, y, transform))
    return monitors


def _build_from_umbriel(umbriel_data, drm_modes):
    saved_cfg = _saved_monitor_prefs()
    disabled_toml = _umbriel_disabled_outputs()
    monitors = []
    seen_names = set()
    for out in umbriel_data:
        name = out.get("name", "Display")
        seen_names.add(name)
        modes = out.get("modes", []) or []
        cur_mode = next((m for m in modes if m.get("current")), None)
        if not cur_mode and modes:
            cur_mode = modes[0]

        w = int(cur_mode.get("width", 1920)) if cur_mode else 1920
        h = int(cur_mode.get("height", 1080)) if cur_mode else 1080
        rate = int(round(int(cur_mode.get("refresh_mhz", 60000) or 60000) / 1000.0)) if cur_mode else 60
        try:
            scale = float(out.get("scale", 1.0) or 1.0)
        except (TypeError, ValueError):
            scale = 1.0
        active = out.get("enabled", True) is not False
        pos = out.get("position")
        if isinstance(pos, (list, tuple)) and len(pos) >= 2:
            x, y = int(pos[0]), int(pos[1])
        elif isinstance(pos, dict):
            x, y = int(pos.get("x", 0) or 0), int(pos.get("y", 0) or 0)
        else:
            x, y = int(out.get("x", 0) or 0), int(out.get("y", 0) or 0)
        transform = _norm_transform(out.get("transform", "normal"))

        res_list, res_rates_map = _collect_mode_table(
            modes,
            rate_fn=lambda m: int(round(int(m.get("refresh_mhz", 60000) or 60000) / 1000.0)),
        )
        if not res_list and name in drm_modes:
            res_list = list(drm_modes[name])

        monitors.append(_make_entry(name, res_list, res_rates_map, f"{w}x{h}", rate, scale, active, x, y, transform))

    for name, info in disabled_toml.items():
        if name in seen_names:
            continue
        saved_m = saved_cfg.get(name, {}) if isinstance(saved_cfg.get(name), dict) else {}
        mode_raw = str(info.get("mode") or saved_m.get("resolution") or "1920x1080@60")
        if "@" in mode_raw:
            cur_res, rate_part = mode_raw.split("@", 1)
            try:
                rate = int(round(float(rate_part)))
            except (TypeError, ValueError):
                rate = 60
        else:
            cur_res = mode_raw
            rate = int(round(float(saved_m.get("framerate", 60) or 60)))
        res_list = list(drm_modes.get(name, [cur_res]))
        res_rates_map = {r: [str(rate)] for r in res_list}
        sc = float(info.get("scale", saved_m.get("scale", 1.0)) or 1.0)
        px = int(info.get("x", saved_m.get("x", 0)) or 0)
        py = int(info.get("y", saved_m.get("y", 0)) or 0)
        monitors.append(_make_entry(name, res_list, res_rates_map, cur_res, rate, sc, False, px, py))
    return monitors


def _merge_positions(monitors, ref_list):
    ref_map = {m["name"]: m for m in (ref_list or []) if isinstance(m, dict) and m.get("name")}
    for m in monitors:
        ref = ref_map.get(m["name"])
        if ref:
            if m["x"] == 0 and m["y"] == 0 and (ref.get("x", 0) != 0 or ref.get("y", 0) != 0):
                m["x"] = ref["x"]
                m["y"] = ref["y"]
            if m["transform"] == "normal" and ref.get("transform", "normal") != "normal":
                m["transform"] = ref["transform"]
    return monitors


def detect_monitors(env=None):
    if env is None:
        env = get_wayland_env()
    drm_modes = get_drm_modes()

    if env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        hypr_monitors = get_hyprland_monitors(env)
        if hypr_monitors:
            return _build_from_hyprland(hypr_monitors)

    if env.get("NIRI_SOCKET"):
        niri_data = get_niri_outputs(env)
        if niri_data:
            return _build_from_niri(niri_data)

    wlr_data = get_wlr_randr(env)
    wlr_monitors = _build_from_wlr_randr(wlr_data, drm_modes) if wlr_data else None

    if env.get("SWAYSOCK"):
        sway_data = get_sway_outputs(env)
        if sway_data:
            monitors = _build_from_sway(sway_data, drm_modes)
            return _merge_positions(monitors, wlr_monitors)

    if env.get("UMBRIEL_SOCKET"):
        umbriel_data = get_umbriel_outputs(env)
        if umbriel_data:
            umb_monitors = _build_from_umbriel(umbriel_data, drm_modes)
            return _merge_positions(umb_monitors, wlr_monitors) if wlr_monitors else umb_monitors

    if wlr_monitors:
        return wlr_monitors

    umbriel_data = get_umbriel_outputs(env)
    if umbriel_data:
        return _build_from_umbriel(umbriel_data, drm_modes)

    # Check Niri/Hyprland even without pre-discovered socket vars
    niri_data = get_niri_outputs(env)
    if niri_data:
        return _build_from_niri(niri_data)

    hypr_monitors = get_hyprland_monitors(env)
    if hypr_monitors:
        return _build_from_hyprland(hypr_monitors)

    # Check driftwm IPC state if running
    try:
        proc = subprocess.run(["driftwm", "msg", "state", "--json"], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            outputs = data.get("Ok", {}).get("State", {}).get("outputs", [])
            if outputs:
                saved_cfg = {}
                try:
                    s_file = os.path.expanduser("~/.config/serpantinum/settings.json")
                    if os.path.exists(s_file):
                        with open(s_file, "r", encoding="utf-8") as sf:
                            saved_cfg = json.load(sf).get("display", {}).get("monitors", {})
                except Exception:
                    pass

                monitors = []
                cur_x = 0
                for out in outputs:
                    name = out.get("name", "eDP-1")
                    sz = out.get("size", [1920, 1080])
                    sc = float(out.get("zoom", 1.0) or 1.0)
                    active = out.get("active", True)
                    cur_res = f"{sz[0]}x{sz[1]}"
                    res_list = list(drm_modes.get(name, [cur_res]))
                    saved_m = saved_cfg.get(name, {}) if isinstance(saved_cfg.get(name), dict) else {}
                    rate = int(round(float(saved_m.get("framerate", 60) or 60)))
                    pos = out.get("position")
                    if isinstance(pos, (list, tuple)) and len(pos) >= 2:
                        px, py = int(pos[0]), int(pos[1])
                    elif saved_m.get("x") is not None or saved_m.get("y") is not None:
                        px, py = int(saved_m.get("x", 0) or 0), int(saved_m.get("y", 0) or 0)
                    else:
                        px, py = cur_x, 0
                    cur_x += max(1, int(round((sz[0] or 1920) / sc)))
                    monitors.append(_make_entry(name, res_list, {r: [str(rate)] for r in res_list}, cur_res, rate, sc, active, px, py))
                return monitors
    except Exception:
        pass

    # Fallback to pure DRM connectors with user saved settings preference
    if drm_modes:
        saved_mon = {}
        try:
            settings_path = os.path.expanduser("~/.config/serpantinum/settings.json")
            if os.path.exists(settings_path):
                with open(settings_path, "r", encoding="utf-8") as sf:
                    saved_mon = json.load(sf).get("display", {}).get("monitors", {})
        except Exception:
            pass

        monitors = []
        cur_x = 0
        for name, modes in drm_modes.items():
            cfg = saved_mon.get(name, {}) if isinstance(saved_mon.get(name), dict) else {}
            top_res = cfg.get("resolution") or (modes[0] if modes else "1920x1080")
            rate = int(round(float(cfg.get("framerate", 60) or 60)))
            scale = float(cfg.get("scale", 1.0) or 1.0)
            px = int(cfg.get("x", cur_x) if cfg.get("x") is not None else cur_x)
            py = int(cfg.get("y", 0) if cfg.get("y") is not None else 0)
            try:
                rw = int(str(top_res).split("x", 1)[0])
            except Exception:
                rw = 1920
            cur_x += max(1, int(round(rw / scale)))
            res_list = list(modes)
            res_rates_map = {m: [str(rate)] for m in res_list}
            monitors.append(_make_entry(name, res_list, res_rates_map, top_res, rate, scale, True, px, py))
        return monitors

    return []


def main():
    print(json.dumps(detect_monitors(get_wayland_env())))


if __name__ == "__main__":
    main()
