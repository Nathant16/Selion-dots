#!/usr/bin/env python3
"""Tests for cross-WM monitor detection, compositor disambiguation, and 2D layout persistence."""

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[2]
SYS_SCRIPTS = REPO_ROOT / "src" / "scripts" / "system"


def _load_module(name: str, path: Path):
    if str(SYS_SCRIPTS) not in sys.path:
        sys.path.insert(0, str(SYS_SCRIPTS))
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


monitors_detector = _load_module("monitors_detector", SYS_SCRIPTS / "monitors_detector.py")
monitor_manager = _load_module("monitor_manager", SYS_SCRIPTS / "monitor_manager.py")


class TestMonitorsDetector(unittest.TestCase):
    def test_builders_preserve_positions_scales_and_rotations(self):
        hypr = monitors_detector._build_from_hyprland([
            {
                "name": "DP-1",
                "width": 3840,
                "height": 2160,
                "refreshRate": 144.0,
                "scale": 1.5,
                "x": 0,
                "y": 0,
                "transform": 0,
                "disabled": False,
                "availableModes": ["3840x2160@144.00Hz", "2560x1440@60.00Hz"],
            },
            {
                "name": "HDMI-A-1",
                "width": 1920,
                "height": 1080,
                "refreshRate": 60.0,
                "scale": 1.0,
                "x": 2560,
                "y": 180,
                "transform": 1,
                "disabled": False,
                "availableModes": ["1920x1080@60.00Hz"],
            },
        ])
        self.assertEqual(hypr[0]["x"], 0)
        self.assertEqual(hypr[0]["scale"], 1.5)
        self.assertEqual(hypr[1]["x"], 2560)
        self.assertEqual(hypr[1]["y"], 180)
        self.assertEqual(hypr[1]["transform"], "90")

        with mock.patch.object(monitors_detector, "_saved_monitor_prefs", return_value={"VDISP-1": {"resolution": "1280x720", "framerate": "60", "scale": 1.0, "x": 320, "y": 1080}}):
            h_dis = monitors_detector._build_from_hyprland([
                {
                    "name": "VDISP-1",
                    "width": 1920,
                    "height": 1080,
                    "refreshRate": 60.0,
                    "scale": 2.0,
                    "x": 0,
                    "y": 0,
                    "transform": 0,
                    "disabled": True,
                    "availableModes": ["1920x1080@60.00Hz"],
                }
            ])
        self.assertFalse(h_dis[0]["active"])
        self.assertEqual(h_dis[0]["dimensions"], "1280x720")
        self.assertEqual(h_dis[0]["x"], 320)
        self.assertEqual(h_dis[0]["y"], 1080)

        niri = monitors_detector._build_from_niri({
            "eDP-1": {
                "modes": [{"width": 1920, "height": 1080, "refresh_rate": 60008, "is_preferred": True}],
                "current_mode": 0,
                "logical": {"x": 120, "y": 40, "scale": 1.25, "transform": "Normal"},
            }
        })
        self.assertEqual(niri[0]["x"], 120)
        self.assertEqual(niri[0]["y"], 40)
        self.assertEqual(niri[0]["scale"], 1.25)

        sway = monitors_detector._build_from_sway([
            {
                "name": "HEADLESS-1",
                "active": True,
                "scale": 1.0,
                "transform": "270",
                "rect": {"x": 320, "y": 1080, "width": 720, "height": 1280},
                "current_mode": {"width": 1280, "height": 720, "refresh": 60000},
                "modes": [{"width": 1280, "height": 720, "refresh": 60000}],
            }
        ], {})
        self.assertEqual(sway[0]["x"], 320)
        self.assertEqual(sway[0]["y"], 1080)
        self.assertEqual(sway[0]["transform"], "270")

    def test_umbriel_detect_retains_virtual_outputs_over_partial_wlr_randr(self):
        umb_payload = [
            {
                "name": "eDP-1",
                "enabled": True,
                "scale": 1.0,
                "position": {"x": 0, "y": 0},
                "transform": "normal",
                "modes": [{"width": 1920, "height": 1080, "refresh_mhz": 60008, "current": True}],
            },
            {
                "name": "VDISP-1",
                "enabled": True,
                "scale": 1.0,
                "position": {"x": 320, "y": 1080},
                "transform": "normal",
                "modes": [{"width": 1280, "height": 720, "refresh_mhz": 60000, "current": True}],
            },
        ]
        wlr_payload = [
            {
                "name": "eDP-1",
                "enabled": True,
                "scale": 1.0,
                "position": {"x": 0, "y": 0},
                "transform": "normal",
                "modes": [{"width": 1920, "height": 1080, "refresh": 60.0, "current": True}],
            }
        ]
        env = {"UMBRIEL_SOCKET": "/run/user/1000/umbriel-wayland-0.sock"}
        with mock.patch.object(monitors_detector, "get_drm_modes", return_value={}), \
             mock.patch.object(monitors_detector, "get_wlr_randr", return_value=wlr_payload), \
             mock.patch.object(monitors_detector, "get_umbriel_outputs", return_value=umb_payload):
            result = monitors_detector.detect_monitors(env)
        self.assertEqual([m["name"] for m in result], ["eDP-1", "VDISP-1"])
        self.assertEqual(result[1]["x"], 320)
        self.assertEqual(result[1]["y"], 1080)

    def test_stale_niri_socket_ignored_when_driftwm_running(self):
        fake_env = {
            "XDG_RUNTIME_DIR": "/tmp/nonexistent-runtime-check",
            "NIRI_SOCKET": "/tmp/stale-niri.sock",
            "UMBRIEL_SOCKET": "/tmp/stale-umbriel.sock",
        }
        with mock.patch.object(monitors_detector.os, "environ", fake_env), \
             mock.patch.object(monitors_detector, "get_running_compositors", return_value={"driftwm"}):
            cleaned = monitors_detector.get_wayland_env()
        self.assertNotIn("NIRI_SOCKET", cleaned)
        self.assertNotIn("UMBRIEL_SOCKET", cleaned)


    def test_disabled_output_recovery_across_niri_sway_umbriel(self):
        saved = {"HDMI-A-1": {"x": 1920, "y": 120, "scale": 1.25, "resolution": "1280x720"}}
        with mock.patch.object(monitors_detector, "_saved_monitor_prefs", return_value=saved):
            niri = monitors_detector._build_from_niri({
                "eDP-1": {
                    "modes": [{"width": 1920, "height": 1080, "refresh_rate": 60000, "is_preferred": True}],
                    "current_mode": 0,
                    "logical": {"x": 0, "y": 0, "scale": 1.0, "transform": "Normal"},
                },
                "HDMI-A-1": {
                    "modes": [{"width": 1280, "height": 720, "refresh_rate": 60000, "is_preferred": True}],
                    "current_mode": 0,
                    "logical": None,
                },
            })
        self.assertFalse(niri[1]["active"])
        self.assertEqual(niri[1]["x"], 1920)
        self.assertEqual(niri[1]["y"], 120)

        with mock.patch.object(monitors_detector, "_saved_monitor_prefs", return_value=saved):
            sway = monitors_detector._build_from_sway([
                {
                    "name": "HDMI-A-1",
                    "active": False,
                    "scale": 1.0,
                    "rect": {"x": 0, "y": 0},
                    "current_mode": None,
                    "modes": [],
                }
            ], {})
        self.assertFalse(sway[0]["active"])
        self.assertEqual(sway[0]["dimensions"], "1280x720")
        self.assertEqual(sway[0]["x"], 1920)

        with mock.patch.object(monitors_detector, "_saved_monitor_prefs", return_value=saved), \
             mock.patch.object(monitors_detector, "_umbriel_disabled_outputs", return_value={"VDISP-1": {"enabled": False, "mode": "1280x720@60", "scale": 1.0, "x": 320, "y": 1080}}):
            umb = monitors_detector._build_from_umbriel([
                {
                    "name": "eDP-1",
                    "enabled": True,
                    "scale": 1.0,
                    "position": {"x": 0, "y": 0},
                    "modes": [{"width": 1920, "height": 1080, "refresh_mhz": 60000, "current": True}],
                }
            ], {})
        self.assertEqual([m["name"] for m in umb], ["eDP-1", "VDISP-1"])
        self.assertFalse(umb[1]["active"])
        self.assertEqual(umb[1]["x"], 320)
        self.assertEqual(umb[1]["y"], 1080)


class TestMonitorManager(unittest.TestCase):
    def test_detect_compositor_prefers_running_compositor_over_stale_sockets(self):
        stale_env = {
            "NIRI_SOCKET": "/run/user/1000/niri.wayland-1.sock",
            "UMBRIEL_SOCKET": "/run/user/1000/umbriel-wayland-0.sock",
        }
        with mock.patch.object(monitor_manager, "_running_compositors", return_value={"driftwm"}):
            self.assertEqual(monitor_manager.detect_compositor(stale_env), "driftwm")
        with mock.patch.object(monitor_manager, "_running_compositors", return_value={"umbriel"}):
            self.assertEqual(monitor_manager.detect_compositor(stale_env), "umbriel")
        with mock.patch.object(monitor_manager, "_running_compositors", return_value={"hyprland"}):
            self.assertEqual(monitor_manager.detect_compositor(stale_env), "hyprland")
        with mock.patch.object(monitor_manager, "_running_compositors", return_value=set()):
            self.assertEqual(monitor_manager.detect_compositor({"SWAYSOCK": "/tmp/s.sock"}), "sway")

    def test_config_persistence_all_six_compositors(self):
        # Hyprland Lua
        hypr_out = monitor_manager._upsert_hypr_block("", "DP-1", "2560x1440@144", "1920x0", 1.25, disabled=True)
        self.assertIn('output = "DP-1"', hypr_out)
        self.assertIn('position = "1920x0"', hypr_out)
        self.assertIn('disabled = true', hypr_out)
        self.assertEqual(monitor_manager._hypr_existing_fields(hypr_out, "DP-1"), ("2560x1440@144", "1920x0", 1.25, True))

        # Sway
        sway_out = monitor_manager._persist_sway_text("", "HEADLESS-1", "1280x720@60Hz", 1.0, (320, 1080), disabled=True)
        self.assertIn("position 320 1080", sway_out)
        self.assertIn("disable\n", sway_out)
        self.assertEqual(monitor_manager._sway_existing_fields(sway_out, "HEADLESS-1"), ((320, 1080), True))

        # Niri KDL
        niri_out = monitor_manager._persist_niri_text("", "eDP-1", "1920x1080@60", 1.25, (120, 40), disabled=True)
        self.assertIn("position x=120 y=40", niri_out)
        self.assertIn("    off\n", niri_out)
        self.assertEqual(monitor_manager._niri_existing_fields(niri_out, "eDP-1"), ((120, 40), True))

        # Mango
        mango_out = monitor_manager._persist_mango_text("", "eDP-1", "1920x1080", "60", 1.0, (120, 40), disabled=True)
        self.assertIn("monitor_rule=name:eDP-1,width:1920,height:1080,refresh:60,scale:1,x:120,y:40,disable:1", mango_out)
        self.assertEqual(monitor_manager._mango_existing_fields(mango_out, "eDP-1"), ((120, 40), True))

        # DriftWM TOML
        drift_src = '[env]\nQT_QPA_PLATFORM = "wayland"\n\n[keybindings]\n"mod+q" = "close"\n'
        drift_out = monitor_manager._persist_driftwm_entry(drift_src, "eDP-1", "1920x1080@60", 1.0, "[120, 40]")
        self.assertIn("[[outputs]]", drift_out)
        self.assertIn("position = [120, 40]", drift_out)
        self.assertLess(drift_out.index("[[outputs]]"), drift_out.index("[keybindings]"))

        # Umbriel TOML
        umb_out = monitor_manager._persist_umbriel_text("", "VDISP-1", "1280x720@60", 1.0, (320, 1080), enabled=False)
        self.assertIn('[output."VDISP-1"]', umb_out)
        self.assertIn("enabled = false", umb_out)
        self.assertIn("position = [320, 1080]", umb_out)
        umb_re = monitor_manager._persist_umbriel_text(umb_out, "VDISP-1", "", 1.25, None)
        self.assertIn("enabled = false", umb_re)
        self.assertIn('mode = "1280x720@60"', umb_re)
        self.assertIn("position = [320, 1080]", umb_re)


if __name__ == "__main__":
    unittest.main()
