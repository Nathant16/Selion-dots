#!/usr/bin/env python3
import json
import subprocess
import glob
import os
import sys

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

def get_drm_modes():
    modes_map = {}
    for p in glob.glob('/sys/class/drm/card*-*/modes'):
        parts = os.path.basename(os.path.dirname(p)).split('-', 1)
        conn = parts[1] if len(parts) > 1 else parts[0]
        try:
            status_p = os.path.join(os.path.dirname(p), 'status')
            if os.path.exists(status_p):
                with open(status_p, 'r') as sf:
                    if sf.read().strip() != 'connected':
                        continue
        except Exception:
            pass
        try:
            with open(p, 'r') as f:
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
        proc = subprocess.run(['wlr-randr', '--json'], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            return json.loads(proc.stdout)
    except Exception:
        pass
    return None

def get_hyprland_monitors(env):
    try:
        proc = subprocess.run(['hyprctl', 'monitors', '-j'], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            return json.loads(proc.stdout)
    except Exception:
        pass
    return None

def get_umbriel_outputs(env):
    try:
        proc = subprocess.run(['umbriel', 'outputs', '--json'], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            if isinstance(data, dict):
                data = list(data.values())
            return data if isinstance(data, list) else None
    except Exception:
        pass
    return None

def main():
    env = get_wayland_env()
    drm_modes = get_drm_modes()
    wlr_data = get_wlr_randr(env)

    # 1. If wlr-randr is available and returned outputs, build comprehensive list
    if wlr_data and isinstance(wlr_data, list):
        monitors = []
        for out in wlr_data:
            name = out.get('name', 'Display')
            cur_mode = next((m for m in out.get('modes', []) if m.get('current')), None)
            if not cur_mode and out.get('modes'):
                cur_mode = out['modes'][0]

            w = cur_mode.get('width', 1920) if cur_mode else 1920
            h = cur_mode.get('height', 1080) if cur_mode else 1080
            rate = cur_mode.get('refresh', 60.0) if cur_mode else 60.0
            scale = out.get('scale', 1.0)
            active = out.get('enabled', True)

            # Available resolutions and refresh rates map
            res_rates_map = {}
            res_list = []
            seen = set()
            for m in out.get('modes', []):
                s = f"{m.get('width')}x{m.get('height')}"
                if s not in seen:
                    seen.add(s)
                    res_list.append(s)
                raw_r = m.get('refresh', 60.0)
                r_str = str(int(round(raw_r)))
                if s not in res_rates_map:
                    res_rates_map[s] = []
                if r_str not in res_rates_map[s]:
                    res_rates_map[s].append(r_str)

            for s in res_rates_map:
                res_rates_map[s].sort(key=lambda x: int(x), reverse=True)

            # Fallback to drm_modes if empty
            if not res_list and name in drm_modes:
                res_list = drm_modes[name]

            # Ensure current resolution is in modes
            cur_res = f"{w}x{h}"
            if cur_res not in res_list:
                res_list.insert(0, cur_res)

            cur_framerates = res_rates_map.get(cur_res, [str(int(round(rate)))])
            if not cur_framerates:
                cur_framerates = [str(int(round(rate)))]

            monitors.append({
                'name': name,
                'dimensions': cur_res,
                'framerate': str(int(round(rate))),
                'framerates': cur_framerates,
                'resolutions_map': res_rates_map,
                'scale': scale,
                'active': active,
                'modes': res_list
            })
        print(json.dumps(monitors))
        return

    # 2. Check Umbriel native IPC if running
    umbriel_data = get_umbriel_outputs(env)
    if umbriel_data:
        monitors = []
        for out in umbriel_data:
            name = out.get('name', 'Display')
            modes = out.get('modes', []) or []
            cur_mode = next((m for m in modes if m.get('current')), None)
            if not cur_mode and modes:
                cur_mode = modes[0]

            w = int(cur_mode.get('width', 1920)) if cur_mode else 1920
            h = int(cur_mode.get('height', 1080)) if cur_mode else 1080
            rate_mhz = int(cur_mode.get('refresh_mhz', 60000) or 60000) if cur_mode else 60000
            rate = int(round(rate_mhz / 1000))
            try:
                scale = float(out.get('scale', 1.0))
            except (TypeError, ValueError):
                scale = 1.0
            active = out.get('enabled', True) is not False

            cur_res = f"{w}x{h}"
            res_rates_map = {}
            res_list = []
            seen = set()
            for m in modes:
                mw = int(m.get('width', 1920))
                mh = int(m.get('height', 1080))
                s = f"{mw}x{mh}"
                if s not in seen:
                    seen.add(s)
                    res_list.append(s)
                mr = int(round(int(m.get('refresh_mhz', 60000) or 60000) / 1000))
                res_rates_map.setdefault(s, [])
                if str(mr) not in res_rates_map[s]:
                    res_rates_map[s].append(str(mr))
            for s in res_rates_map:
                res_rates_map[s].sort(key=lambda x: int(x), reverse=True)
            if cur_res not in res_list:
                res_list.insert(0, cur_res)
            cur_framerates = res_rates_map.get(cur_res, [str(rate)])

            monitors.append({
                'name': name,
                'dimensions': cur_res,
                'framerate': str(rate),
                'framerates': cur_framerates,
                'resolutions_map': res_rates_map,
                'scale': scale,
                'active': active,
                'modes': res_list
            })
        print(json.dumps(monitors))
        return

    # 3. Check driftwm IPC state if running
    try:
        proc = subprocess.run(['driftwm', 'msg', 'state', '--json'], capture_output=True, text=True, timeout=2, env=env)
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            outputs = data.get('Ok', {}).get('State', {}).get('outputs', [])
            if outputs:
                # Check saved framerate from settings.json if available
                saved_cfg = {}
                try:
                    s_file = os.path.expanduser('~/.config/serpantinum/settings.json')
                    if os.path.exists(s_file):
                        with open(s_file, 'r', encoding='utf-8') as sf:
                            saved_cfg = json.load(sf).get('display', {}).get('monitors', {})
                except Exception:
                    pass

                monitors = []
                for out in outputs:
                    name = out.get('name', 'eDP-1')
                    sz = out.get('size', [1920, 1080])
                    sc = out.get('zoom', 1.0)
                    active = out.get('active', True)
                    cur_res = f"{sz[0]}x{sz[1]}"
                    res_list = drm_modes.get(name, [cur_res])
                    if cur_res not in res_list:
                        res_list.insert(0, cur_res)

                    saved_m = saved_cfg.get(name, {})
                    rate = saved_m.get('framerate', '60') if isinstance(saved_m, dict) else '60'

                    monitors.append({
                        'name': name,
                        'dimensions': cur_res,
                        'framerate': str(rate),
                        'scale': sc,
                        'active': active,
                        'modes': res_list
                    })
                print(json.dumps(monitors))
                return
    except Exception:
        pass

    # 3. Check Hyprland native IPC
    hypr_monitors = get_hyprland_monitors(env)
    if hypr_monitors and isinstance(hypr_monitors, list):
        monitors = []
        for out in hypr_monitors:
            name = out.get('name', 'eDP-1')
            w = out.get('width', 1920)
            h = out.get('height', 1080)
            rate = out.get('refreshRate', 60.0)
            scale = out.get('scale', 1.0)
            active = not out.get('disabled', False)
            cur_res = f"{w}x{h}"

            res_rates_map = {}
            res_list = []
            seen = set()
            for m_str in out.get('availableModes', []):
                try:
                    mode_part, hz_part = m_str.split('@', 1)
                    mode_part = mode_part.strip()
                    hz_val = float(hz_part.replace('Hz', '').strip())
                    r_str = str(int(round(hz_val)))
                    if mode_part not in seen:
                        seen.add(mode_part)
                        res_list.append(mode_part)
                    if mode_part not in res_rates_map:
                        res_rates_map[mode_part] = []
                    if r_str not in res_rates_map[mode_part]:
                        res_rates_map[mode_part].append(r_str)
                except Exception:
                    pass

            for s in res_rates_map:
                res_rates_map[s].sort(key=lambda x: int(x), reverse=True)

            if cur_res not in res_list:
                res_list.insert(0, cur_res)

            cur_framerates = res_rates_map.get(cur_res, [str(int(round(rate)))])
            if not cur_framerates:
                cur_framerates = [str(int(round(rate)))]

            monitors.append({
                'name': name,
                'dimensions': cur_res,
                'framerate': str(int(round(rate))),
                'framerates': cur_framerates,
                'resolutions_map': res_rates_map,
                'scale': scale,
                'active': active,
                'modes': res_list
            })
        print(json.dumps(monitors))
        return

    # 4. Fallback to pure DRM connectors with user saved settings preference
    if drm_modes:
        saved_resolutions = {}
        saved_rates = {}
        try:
            settings_path = os.path.expanduser('~/.config/serpantinum/settings.json')
            if os.path.exists(settings_path):
                with open(settings_path, 'r', encoding='utf-8') as sf:
                    s_data = json.load(sf)
                    mon_conf = s_data.get('display', {}).get('monitors', {})
                    for m_name, m_cfg in mon_conf.items():
                        if isinstance(m_cfg, dict):
                            if m_cfg.get('resolution'):
                                saved_resolutions[m_name] = m_cfg.get('resolution')
                            if m_cfg.get('framerate'):
                                saved_rates[m_name] = str(m_cfg.get('framerate'))
        except Exception:
            pass

        monitors = []
        for name, modes in drm_modes.items():
            top_res = saved_resolutions.get(name) or (modes[0] if modes else "1920x1080")
            if modes and top_res not in modes:
                modes.insert(0, top_res)
            rate = saved_rates.get(name, "60")
            res_rates_map = {m: [rate] for m in modes}
            monitors.append({
                'name': name,
                'dimensions': top_res,
                'framerate': rate,
                'framerates': [rate],
                'resolutions_map': res_rates_map,
                'scale': 1.0,
                'active': True,
                'modes': modes
            })
        print(json.dumps(monitors))
        return

    print("[]")

if __name__ == '__main__':
    main()
