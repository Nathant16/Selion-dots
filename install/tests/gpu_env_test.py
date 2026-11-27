#!/usr/bin/env python3
"""Tests for cross-WM GPU profile detection and env config generation."""

import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

try:
    import tomllib
except ImportError:
    tomllib = None

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "src" / "scripts" / "system"))

import gpu_env  # noqa: E402


class TestGpuEnv(unittest.TestCase):
    def test_nvidia_only_with_and_without_vaapi(self):
        with_va = gpu_env.build_gpu_env("nvidia-only", True)
        self.assertTrue(with_va["nvidia_proprietary"])
        self.assertTrue(with_va["no_hardware_cursors"])
        self.assertIn(("LIBVA_DRIVER_NAME", "nvidia"), with_va["core_env"])
        self.assertIn(("__GLX_VENDOR_LIBRARY_NAME", "nvidia"), with_va["core_env"])
        self.assertIn(("NVD_BACKEND", "direct"), with_va["core_env"])
        self.assertEqual([("WLR_NO_HARDWARE_CURSORS", "1")], with_va["wlroots_env"])

        no_va = gpu_env.build_gpu_env("nvidia-only", False)
        self.assertNotIn(("NVD_BACKEND", "direct"), no_va["core_env"])

    def test_hybrid_amd_and_intel_nvidia(self):
        for profile in ("hybrid-intel-nvidia", "hybrid-amd-nvidia"):
            info = gpu_env.build_gpu_env(profile, False)
            self.assertTrue(info["nvidia_proprietary"])
            self.assertTrue(info["no_hardware_cursors"])
            self.assertIn(("__GLX_VENDOR_LIBRARY_NAME", "nvidia"), info["core_env"])
            self.assertIn(("VK_LAYER_NV_optimus", "1"), info["core_env"])

    def test_non_nvidia_profiles_stay_clean(self):
        for profile in ("amd-only", "intel-only", "hybrid-amd-intel", "nouveau-only", "unknown"):
            info = gpu_env.build_gpu_env(profile, False)
            self.assertFalse(info["nvidia_proprietary"])
            self.assertFalse(info["no_hardware_cursors"])
            self.assertEqual([], info["core_env"])
            self.assertEqual([], info["wlroots_env"])

    def test_apply_gpu_env_transitions_idempotently(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp)
            (cfg / "niri" / "default").mkdir(parents=True)
            (cfg / "mango" / "default").mkdir(parents=True)
            (cfg / "umbriel").mkdir(parents=True)
            (cfg / "driftwm").mkdir(parents=True)
            shutil.copy(REPO_ROOT / "compositors/niri/default/gpu-env.kdl", cfg / "niri/default/gpu-env.kdl")
            shutil.copy(REPO_ROOT / "compositors/mango/default/gpu-env.conf", cfg / "mango/default/gpu-env.conf")
            shutil.copy(REPO_ROOT / "compositors/umbriel/config.toml", cfg / "umbriel/config.toml")
            shutil.copy(REPO_ROOT / "compositors/driftwm/config.toml", cfg / "driftwm/config.toml")

            old_override = os.environ.get("GPU_SETUP")
            try:
                os.environ["GPU_SETUP"] = "nvidia-only"
                gpu_env.apply_gpu_env(cfg)

                envd = cfg / "environment.d" / "90-serpantinum-gpu.conf"
                self.assertTrue(envd.is_file())
                self.assertIn("LIBVA_DRIVER_NAME=nvidia", envd.read_text(encoding="utf-8"))
                self.assertIn("LIBVA_DRIVER_NAME", (cfg / "niri/default/gpu-env-auto.kdl").read_text(encoding="utf-8"))
                self.assertNotIn("WLR_NO_HARDWARE_CURSORS", (cfg / "niri/default/gpu-env-auto.kdl").read_text(encoding="utf-8"))
                self.assertIn("env=WLR_NO_HARDWARE_CURSORS,1", (cfg / "mango/default/gpu-env-auto.conf").read_text(encoding="utf-8"))
                self.assertIn("WLR_NO_HARDWARE_CURSORS", (cfg / "umbriel/config.toml").read_text(encoding="utf-8"))
                self.assertNotIn("WLR_NO_HARDWARE_CURSORS", (cfg / "driftwm/config.toml").read_text(encoding="utf-8"))
                self.assertIn("LIBVA_DRIVER_NAME", (cfg / "driftwm/config.toml").read_text(encoding="utf-8"))

                if tomllib is not None:
                    with open(cfg / "umbriel/config.toml", "rb") as f:
                        umb = tomllib.load(f)
                    with open(cfg / "driftwm/config.toml", "rb") as f:
                        drift = tomllib.load(f)
                    self.assertEqual("1", umb["environment"]["WLR_NO_HARDWARE_CURSORS"])
                    self.assertEqual("nvidia", drift["env"]["LIBVA_DRIVER_NAME"])

                os.environ["GPU_SETUP"] = "amd-only"
                gpu_env.apply_gpu_env(cfg)
                self.assertFalse(envd.exists())
                self.assertNotIn("nvidia", (cfg / "niri/default/gpu-env-auto.kdl").read_text(encoding="utf-8"))
                self.assertNotIn("nvidia", (cfg / "mango/default/gpu-env-auto.conf").read_text(encoding="utf-8"))
                self.assertNotIn("WLR_NO_HARDWARE_CURSORS", (cfg / "umbriel/config.toml").read_text(encoding="utf-8"))
                self.assertNotIn("LIBVA_DRIVER_NAME", (cfg / "driftwm/config.toml").read_text(encoding="utf-8"))

                if tomllib is not None:
                    with open(cfg / "umbriel/config.toml", "rb") as f:
                        tomllib.load(f)
                    with open(cfg / "driftwm/config.toml", "rb") as f:
                        tomllib.load(f)
            finally:
                if old_override is None:
                    os.environ.pop("GPU_SETUP", None)
                else:
                    os.environ["GPU_SETUP"] = old_override


if __name__ == "__main__":
    unittest.main()
