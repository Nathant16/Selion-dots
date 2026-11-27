#!/usr/bin/env python3
"""Detect active GPU configuration and sync per-compositor GPU env configs."""

import argparse
import json
import os
from pathlib import Path

START_MARKER = "# >>> SELION_GPU_ENV_START"
END_MARKER = "# <<< SELION_GPU_ENV_END"


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def has_nvidia_vaapi() -> bool:
    return any(
        Path(p).is_file()
        for p in (
            "/usr/lib/dri/nvidia_drv_video.so",
            "/usr/lib64/dri/nvidia_drv_video.so",
        )
    )


def detect_gpu_setup() -> str:
    override = os.environ.get("GPU_SETUP", "").strip()
    if override:
        return override

    has_nvidia = False
    has_nouveau = False
    has_amd = False
    has_intel = False

    pci_root = Path("/sys/bus/pci/devices")
    if pci_root.is_dir():
        for dev in sorted(pci_root.iterdir()):
            cls = _read_text(dev / "class")
            if not cls.startswith("0x03"):
                continue
            vendor = _read_text(dev / "vendor").lower()
            driver = ""
            drv_link = dev / "driver"
            if drv_link.is_symlink():
                try:
                    driver = os.path.basename(os.readlink(drv_link))
                except OSError:
                    driver = ""

            if vendor == "0x10de":
                if driver == "nouveau":
                    has_nouveau = True
                else:
                    has_nvidia = True
            elif vendor == "0x1002":
                has_amd = True
            elif vendor == "0x8086":
                has_intel = True

    if has_nvidia:
        if has_intel:
            return "hybrid-intel-nvidia"
        if has_amd:
            return "hybrid-amd-nvidia"
        return "nvidia-only"
    if has_amd and has_intel:
        return "hybrid-amd-intel"
    if has_amd:
        return "amd-only"
    if has_nouveau:
        if has_intel:
            return "hybrid-intel-nouveau"
        if has_amd:
            return "hybrid-amd-nouveau"
        return "nouveau-only"
    if has_intel:
        return "intel-only"
    return "unknown"


def build_gpu_env(setup: str, vaapi: bool) -> dict:
    """Return shared, wlroots-only, and cursor tuning for the detected setup."""
    core_env = []
    if setup == "nvidia-only":
        core_env = [
            ("LIBVA_DRIVER_NAME", "nvidia"),
            ("__GLX_VENDOR_LIBRARY_NAME", "nvidia"),
            ("__GL_VRR_ALLOWED", "1"),
        ]
        if vaapi:
            core_env.append(("NVD_BACKEND", "direct"))
        return {
            "setup": setup,
            "vaapi": vaapi,
            "nvidia_proprietary": True,
            "no_hardware_cursors": True,
            "core_env": core_env,
            "wlroots_env": [("WLR_NO_HARDWARE_CURSORS", "1")],
        }

    if setup in ("hybrid-intel-nvidia", "hybrid-amd-nvidia"):
        core_env = [
            ("__GLX_VENDOR_LIBRARY_NAME", "nvidia"),
            ("VK_LAYER_NV_optimus", "1"),
        ]
        if vaapi:
            core_env.append(("NVD_BACKEND", "direct"))
        return {
            "setup": setup,
            "vaapi": vaapi,
            "nvidia_proprietary": True,
            "no_hardware_cursors": True,
            "core_env": core_env,
            "wlroots_env": [("WLR_NO_HARDWARE_CURSORS", "1")],
        }

    return {
        "setup": setup,
        "vaapi": vaapi,
        "nvidia_proprietary": False,
        "no_hardware_cursors": False,
        "core_env": [],
        "wlroots_env": [],
    }


def _write_if_changed(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        try:
            if path.read_text(encoding="utf-8") == content:
                return
        except OSError:
            pass
    path.write_text(content, encoding="utf-8")


def _update_toml_env_block(path: Path, section_header: str, pairs: list[tuple[str, str]], setup: str) -> None:
    if not path.is_file():
        return
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        return

    lines = raw.splitlines()
    out = []
    skip = False
    for line in lines:
        s = line.strip()
        if s == START_MARKER:
            skip = True
            continue
        if s == END_MARKER:
            skip = False
            continue
        if not skip:
            out.append(line)

    block_lines = [START_MARKER, f"# Auto-managed for GPU profile: {setup}"]
    for k, v in pairs:
        block_lines.append(f'{k} = "{v}"')
    block_lines.append(END_MARKER)

    try:
        sec_idx = next(i for i, ln in enumerate(out) if ln.strip() == section_header)
    except StopIteration:
        return

    insert_at = len(out)
    for i in range(sec_idx + 1, len(out)):
        s = out[i].strip()
        if s.startswith("[") and s.endswith("]"):
            insert_at = i
            break

    while insert_at > sec_idx + 1 and out[insert_at - 1].strip() == "":
        insert_at -= 1

    new_lines = out[:insert_at] + block_lines + out[insert_at:]
    new_content = "\n".join(new_lines) + "\n"
    if new_content != raw:
        path.write_text(new_content, encoding="utf-8")


def apply_gpu_env(config_home: Path | None = None) -> dict:
    cfg = config_home or Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    info = build_gpu_env(detect_gpu_setup(), has_nvidia_vaapi())
    setup = info["setup"]
    core_pairs = info["core_env"]
    wlr_pairs = info["wlroots_env"] + core_pairs

    # 1. systemd user environment.d (used by Sway, SDDM/systemd sessions, portals)
    envd_file = cfg / "environment.d" / "90-serpantinum-gpu.conf"
    if wlr_pairs:
        envd_lines = [
            f"# Auto-generated by Serpantinum gpu_env.py for profile: {setup}",
            *(f"{k}={v}" for k, v in wlr_pairs),
            "",
        ]
        _write_if_changed(envd_file, "\n".join(envd_lines))
    elif envd_file.exists():
        try:
            envd_file.unlink()
        except OSError:
            pass

    # 2. Niri: ~/.config/niri/default/gpu-env-auto.kdl (Smithay, no WLR_*)
    niri_dir = cfg / "niri" / "default"
    if niri_dir.is_dir():
        if core_pairs:
            kdl_lines = [
                f"// Auto-generated by Serpantinum gpu_env.py for profile: {setup}",
                "environment {",
                *(f'    {k} "{v}"' for k, v in core_pairs),
                "}",
                "",
            ]
        else:
            kdl_lines = [
                f"// Auto-generated by Serpantinum gpu_env.py for profile: {setup} (no overrides needed)",
                "",
            ]
        _write_if_changed(niri_dir / "gpu-env-auto.kdl", "\n".join(kdl_lines))

    # 3. MangoWC: ~/.config/mango/default/gpu-env-auto.conf (wlroots)
    mango_dir = cfg / "mango" / "default"
    if mango_dir.is_dir():
        if wlr_pairs:
            mango_lines = [
                f"# Auto-generated by Serpantinum gpu_env.py for profile: {setup}",
                *(f"env={k},{v}" for k, v in wlr_pairs),
                "",
            ]
        else:
            mango_lines = [
                f"# Auto-generated by Serpantinum gpu_env.py for profile: {setup} (no overrides needed)",
                "",
            ]
        _write_if_changed(mango_dir / "gpu-env-auto.conf", "\n".join(mango_lines))

    # 4. Umbriel: ~/.config/umbriel/config.toml ([environment], wlroots)
    umbriel_cfg = cfg / "umbriel" / "config.toml"
    if umbriel_cfg.is_file():
        _update_toml_env_block(umbriel_cfg, "[environment]", wlr_pairs, setup)

    # 5. DriftWM: ~/.config/driftwm/config.toml ([env], Smithay)
    drift_cfg = cfg / "driftwm" / "config.toml"
    if drift_cfg.is_file():
        _update_toml_env_block(drift_cfg, "[env]", core_pairs, setup)

    return info


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect GPU profile and configure Wayland WM environments.")
    parser.add_argument("--profile", action="store_true", help="Print detected GPU profile name")
    parser.add_argument("--json", action="store_true", help="Print detected GPU info as JSON")
    parser.add_argument("--apply", action="store_true", help="Generate/update WM GPU environment configs")
    parser.add_argument("--config-dir", type=Path, default=None, help="Override XDG_CONFIG_HOME target")
    args = parser.parse_args()

    if args.apply:
        info = apply_gpu_env(args.config_dir)
    else:
        info = build_gpu_env(detect_gpu_setup(), has_nvidia_vaapi())

    if args.json:
        print(json.dumps(info, indent=2))
    elif args.profile or not args.apply:
        print(info["setup"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
