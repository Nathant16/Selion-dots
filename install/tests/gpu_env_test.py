#!/usr/bin/env python3
"""Tests for cross-WM GPU profile detection and env config generation."""

import importlib
import importlib.util
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


def _load_toml_parser() -> Any:
    """Return stdlib tomllib (3.11+) or tomli if available."""
    for mod_name in ("tomllib", "tomli"):
        if importlib.util.find_spec(mod_name) is not None:
            return importlib.import_module(mod_name)
    return None


def _load_gpu_env(repo_root: Path) -> Any:
    """Load gpu_env directly by file path so static analyzers resolve imports cleanly."""
    module_path = repo_root / "src" / "scripts" / "system" / "gpu_env.py"
    spec = importlib.util.spec_from_file_location("gpu_env", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec for {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["gpu_env"] = module
    spec.loader.exec_module(module)
    return module


toml_parser = _load_toml_parser()
REPO_ROOT = Path(__file__).resolve().parents[2]
gpu_env = _load_gpu_env(REPO_ROOT)


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

                if toml_parser is not None:
                    with open(cfg / "umbriel/config.toml", "rb") as f:
                        umb = toml_parser.load(f)
                    with open(cfg / "driftwm/config.toml", "rb") as f:
                        drift = toml_parser.load(f)
                    self.assertEqual("1", umb["environment"]["WLR_NO_HARDWARE_CURSORS"])
                    self.assertEqual("nvidia", drift["env"]["LIBVA_DRIVER_NAME"])

                os.environ["GPU_SETUP"] = "amd-only"
                gpu_env.apply_gpu_env(cfg)
                self.assertFalse(envd.exists())
                self.assertNotIn("nvidia", (cfg / "niri/default/gpu-env-auto.kdl").read_text(encoding="utf-8"))
                self.assertNotIn("nvidia", (cfg / "mango/default/gpu-env-auto.conf").read_text(encoding="utf-8"))
                self.assertNotIn("WLR_NO_HARDWARE_CURSORS", (cfg / "umbriel/config.toml").read_text(encoding="utf-8"))
                self.assertNotIn("LIBVA_DRIVER_NAME", (cfg / "driftwm/config.toml").read_text(encoding="utf-8"))

                if toml_parser is not None:
                    with open(cfg / "umbriel/config.toml", "rb") as f:
                        toml_parser.load(f)
                    with open(cfg / "driftwm/config.toml", "rb") as f:
                        toml_parser.load(f)
            finally:
                if old_override is None:
                    os.environ.pop("GPU_SETUP", None)
                else:
                    os.environ["GPU_SETUP"] = old_override


if __name__ == "__main__":
    unittest.main()
