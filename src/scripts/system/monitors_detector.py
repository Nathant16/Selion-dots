#!/usr/bin/env python3
import json
import subprocess
import glob
import os
import sys

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

def get_wlr_randr():
    try:
        proc = subprocess.run(['wlr-randr', '--json'], capture_output=True, text=True, timeout=2)
        if proc.returncode == 0 and proc.stdout.strip():
            return json.loads(proc.stdout)
    except Exception:
        pass
    return None

def main():
    drm_modes = get_drm_modes()
    wlr_data = get_wlr_randr()

    # If wlr-randr is available and returned outputs, build comprehensive list
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

            # Available resolutions
            res_list = []
            seen = set()
            for m in out.get('modes', []):
                s = f"{m.get('width')}x{m.get('height')}"
                if s not in seen:
                    seen.add(s)
                    res_list.append(s)

            # Fallback to drm_modes if empty
            if not res_list and name in drm_modes:
                res_list = drm_modes[name]

            monitors.append({
                'name': name,
                'dimensions': f"{w}x{h}",
                'framerate': str(int(round(rate))),
                'scale': scale,
                'active': active,
                'modes': res_list
            })
        print(json.dumps(monitors))
        return

    # Check driftwm IPC state if running
    try:
        proc = subprocess.run(['driftwm', 'msg', 'state', '--json'], capture_output=True, text=True, timeout=2)
        if proc.returncode == 0:
            data = json.loads(proc.stdout)
            outputs = data.get('Ok', {}).get('State', {}).get('outputs', [])
            if outputs:
                monitors = []
                for out in outputs:
                    name = out.get('name', 'eDP-1')
                    sz = out.get('size', [1920, 1080])
                    sc = out.get('zoom', 1.0)
                    active = out.get('active', True)
                    res_list = drm_modes.get(name, [f"{sz[0]}x{sz[1]}"])
                    monitors.append({
                        'name': name,
                        'dimensions': f"{sz[0]}x{sz[1]}",
                        'framerate': "60",
                        'scale': sc,
                        'active': active,
                        'modes': res_list
                    })
                print(json.dumps(monitors))
                return
    except Exception:
        pass

    # Fallback to pure DRM connectors
    if drm_modes:
        monitors = []
        for name, modes in drm_modes.items():
            top_res = modes[0] if modes else "1920x1080"
            monitors.append({
                'name': name,
                'dimensions': top_res,
                'framerate': "60",
                'scale': 1.0,
                'active': True,
                'modes': modes
            })
        print(json.dumps(monitors))
        return

    print("[]")

if __name__ == '__main__':
    main()
