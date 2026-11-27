#!/usr/bin/env python3
"""Tests for built-in Antigravity IDE app theming preset."""

import contextlib
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_mod(name: str, rel_path: str) -> Any:
    mod_path = REPO_ROOT / rel_path
    spec = importlib.util.spec_from_file_location(name, mod_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load {mod_path}")
    mod = importlib.util.module_from_spec(spec)
    mod.__file__ = str(mod_path)
    import sys
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


apptheme_mod = _load_mod("apptheme", "src/scripts/theming/apptheme.py")


class TestAntigravityTheme(unittest.TestCase):
    @contextlib.contextmanager
    def _sandbox(self, mode: str = "dark"):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            home = tmp / "home"
            cfg = home / ".config"
            cache = home / ".cache"
            state = home / ".local" / "state" / "serpantinum"
            data_home = home / ".local" / "share"
            (cfg / "serpantinum").mkdir(parents=True)
            (state / "matugen").mkdir(parents=True)
            cache.mkdir(parents=True)
            data_home.mkdir(parents=True)

            palette = {
                "surface": "#14140c",
                "surface_variant": "#49473a",
                "surface_container_low": "#1d1c14",
                "surface_container": "#212018",
                "surface_container_high": "#2b2a22",
                "surface_container_highest": "#36352c",
                "on_surface": "#e6e2d5",
                "on_surface_variant": "#cac7b5",
                "outline": "#949181",
                "outline_variant": "#49473a",
                "primary": "#cfca74",
                "on_primary": "#343200",
                "primary_container": "#4c4900",
                "primary_fixed": "#ece68d",
                "primary_fixed_dim": "#cfca74",
                "inverse_primary": "#646116",
                "secondary": "#ccc8a4",
                "secondary_container": "#4a482c",
                "on_secondary_container": "#e8e4be",
                "secondary_fixed": "#e8e4be",
                "secondary_fixed_dim": "#ccc8a4",
                "tertiary": "#a5d0bb",
                "on_tertiary": "#0d3728",
                "tertiary_container": "#264e3e",
                "tertiary_fixed": "#c0ecd6",
                "tertiary_fixed_dim": "#a5d0bb",
                "error": "#ffb4ab",
                "error_container": "#93000a",
            }
            palette_doc = {
                "colors": {
                    k: {"default": {"hex": v}, "dark": {"hex": v}, "light": {"hex": v}}
                    for k, v in palette.items()
                }
            }
            (state / "matugen/palette.json").write_text(json.dumps(palette_doc), encoding="utf-8")
            (cfg / "serpantinum/settings.json").write_text(
                json.dumps({"theme": {"mode": mode, "apps": ["antigravity"]}}),
                encoding="utf-8",
            )

            old_env = os.environ.copy()
            try:
                os.environ["HOME"] = str(home)
                os.environ["XDG_CONFIG_HOME"] = str(cfg)
                os.environ["XDG_CACHE_HOME"] = str(cache)
                os.environ["XDG_DATA_HOME"] = str(data_home)
                os.environ["XDG_STATE_HOME"] = str(home / ".local" / "state")
                os.environ["QS_STATE_DIR"] = str(state)
                os.environ["QS_SETTINGS"] = str(cfg / "serpantinum/settings.json")
                os.environ["SERPANTINUM_APPTHEME_BUILTIN"] = str(REPO_ROOT / "src/assets/matugen/apps")
                apptheme_mod._PATH_CACHE.clear()
                yield home, cfg, cache, state
            finally:
                os.environ.clear()
                os.environ.update(old_env)
                apptheme_mod._PATH_CACHE.clear()

    def test_builtin_manifest_listed_and_valid(self):
        with self._sandbox() as (_home, cfg, _cache, _state):
            (cfg / "Antigravity IDE" / "User").mkdir(parents=True)
            ctx = apptheme_mod.Context()
            listing = apptheme_mod.list_apps(ctx)
            entry = next((a for a in listing["apps"] if a["id"] == "antigravity"), None)
            self.assertIsNotNone(entry)
            self.assertEqual(entry["name"], "Antigravity")
            self.assertEqual(entry["category"], "editors")
            self.assertEqual(entry["error"], "")
            self.assertTrue(entry["installed"])
            self.assertTrue(entry["enabled"])

    def test_apply_preserves_user_settings_and_undo_restores(self):
        with self._sandbox(mode="dark") as (_home, cfg, cache, _state):
            ide_settings = cfg / "Antigravity IDE" / "User" / "settings.json"
            std_settings = cfg / "Antigravity" / "User" / "settings.json"
            ide_settings.parent.mkdir(parents=True)
            std_settings.parent.mkdir(parents=True)

            original_ide = json.dumps(
                {
                    "editor.fontSize": 13,
                    "antigravity-proxy.autoStart": True,
                    "python.languageServer": "Default",
                },
                indent=2,
            ) + "\n"
            ide_settings.write_text(original_ide, encoding="utf-8")
            std_settings.write_text("{}\n", encoding="utf-8")

            ctx = apptheme_mod.Context()
            res = apptheme_mod.apply(ctx, only=["antigravity"])
            self.assertTrue(res["ok"], res)
            self.assertTrue(res["apps"]["antigravity"]["ok"], res)
            self.assertEqual(res["apps"]["antigravity"]["issues"], [])
            self.assertTrue((cache / "serpantinum/apps/antigravity.json").is_file())

            updated_ide = json.loads(ide_settings.read_text(encoding="utf-8"))
            self.assertEqual(updated_ide["editor.fontSize"], 13)
            self.assertTrue(updated_ide["antigravity-proxy.autoStart"])
            self.assertEqual(updated_ide["python.languageServer"], "Default")
            self.assertEqual(updated_ide["workbench.colorTheme"], "Default Dark Modern")
            self.assertEqual(updated_ide["workbench.colorCustomizations"]["editor.background"], "#14140c")
            self.assertEqual(updated_ide["workbench.colorCustomizations"]["chat.requestBackground"], "#212018")
            self.assertIn("textMateRules", updated_ide["editor.tokenColorCustomizations"])

            updated_std = json.loads(std_settings.read_text(encoding="utf-8"))
            self.assertEqual(updated_std["workbench.colorTheme"], "Default Dark Modern")

            # Switch to light mode
            (cfg / "serpantinum/settings.json").write_text(
                json.dumps({"theme": {"mode": "light", "apps": ["antigravity"]}}),
                encoding="utf-8",
            )
            res_light = apptheme_mod.apply(ctx, only=["antigravity"])
            self.assertTrue(res_light["ok"], res_light)
            light_ide = json.loads(ide_settings.read_text(encoding="utf-8"))
            self.assertEqual(light_ide["workbench.colorTheme"], "Default Light Modern")

            # Customize + Undo restores original settings.json cleanly
            cust = apptheme_mod.customize(ctx, "antigravity")
            self.assertTrue(cust["ok"])
            self.assertTrue((cfg / "serpantinum/matugen/apps/antigravity/app.json").is_file())
            self.assertTrue((cfg / "serpantinum/matugen/apps/antigravity/colors.json").is_file())

            undone = apptheme_mod.undo(ctx, ["antigravity"])
            self.assertEqual(undone["undone"], ["antigravity"])
            restored_ide = json.loads(ide_settings.read_text(encoding="utf-8"))
            self.assertEqual(
                restored_ide,
                {
                    "editor.fontSize": 13,
                    "antigravity-proxy.autoStart": True,
                    "python.languageServer": "Default",
                },
            )


if __name__ == "__main__":
    unittest.main()
