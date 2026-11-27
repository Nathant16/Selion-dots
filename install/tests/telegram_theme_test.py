#!/usr/bin/env python3
"""Tests for built-in Telegram / AyuGram palette preset."""

import contextlib
import importlib.util
import json
import os
import re
import sys
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
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


apptheme_mod = _load_mod("apptheme", "src/scripts/theming/apptheme.py")


class TestTelegramTheme(unittest.TestCase):
    @contextlib.contextmanager
    def _sandbox(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            home = tmp / "home"
            cfg = home / ".config"
            cache = home / ".cache"
            data_home = home / ".local" / "share"
            state = home / ".local" / "state" / "serpantinum"
            (cfg / "serpantinum").mkdir(parents=True)
            (state / "matugen").mkdir(parents=True)
            cache.mkdir(parents=True)
            data_home.mkdir(parents=True)

            palette = {
                "surface": "#14140c",
                "surface_container_lowest": "#0f0e08",
                "surface_container_low": "#1d1c14",
                "surface_container": "#212018",
                "surface_container_high": "#2b2a22",
                "surface_container_highest": "#36352c",
                "on_surface": "#e6e2d5",
                "on_surface_variant": "#cac7b5",
                "inverse_surface": "#e6e2d5",
                "inverse_on_surface": "#323027",
                "outline": "#949181",
                "outline_variant": "#49473a",
                "primary": "#cfca74",
                "on_primary": "#343200",
                "primary_container": "#4c4900",
                "on_primary_container": "#ece68d",
                "primary_fixed_dim": "#cfca74",
                "inverse_primary": "#646116",
                "secondary": "#ccc8a4",
                "secondary_container": "#4a482c",
                "on_secondary_container": "#e8e4be",
                "error": "#ffb4ab",
                "on_error": "#690005",
                "error_container": "#93000a",
                "shadow": "#000000",
                "scrim": "#000000",
            }
            palette_doc = {
                "colors": {
                    k: {"default": {"hex": v}}
                    for k, v in palette.items()
                }
            }
            (state / "matugen/palette.json").write_text(json.dumps(palette_doc), encoding="utf-8")
            (cfg / "serpantinum/settings.json").write_text(
                json.dumps({"theme": {"mode": "dark", "apps": ["telegram"]}}),
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
                yield home, cfg, data_home
            finally:
                os.environ.clear()
                os.environ.update(old_env)
                apptheme_mod._PATH_CACHE.clear()

    def test_detect_ayugram_apply_palette_and_undo(self):
        with self._sandbox() as (_home, cfg, data_home):
            (data_home / "AyuGramDesktop").mkdir(parents=True)
            ctx = apptheme_mod.Context()
            listing = apptheme_mod.list_apps(ctx)
            entry = next((a for a in listing["apps"] if a["id"] == "telegram"), None)
            self.assertIsNotNone(entry)
            self.assertEqual(entry["name"], "Telegram / AyuGram")
            self.assertEqual(entry["category"], "apps")
            self.assertEqual(entry["hint"], "telegram")
            self.assertTrue(entry["installed"])
            self.assertEqual(entry["error"], "")

            res = apptheme_mod.apply(ctx, only=["telegram"])
            self.assertTrue(res["ok"], res)

            tg_pal = cfg / "telegram-desktop/themes/serpantinum.tdesktop-palette"
            ayu_pal = data_home / "AyuGramDesktop/themes/serpantinum.tdesktop-palette"
            self.assertTrue(tg_pal.is_file())
            self.assertTrue(ayu_pal.is_file())
            self.assertFalse((data_home / "TelegramDesktop/themes/serpantinum.tdesktop-palette").exists())

            for line in ayu_pal.read_text(encoding="utf-8").splitlines():
                self.assertRegex(line, r"^[a-zA-Z_]+: (#[0-9a-f]{6}([0-9a-f]{2})?|[a-zA-Z]+);$")

            undone = apptheme_mod.undo(ctx, ["telegram"])
            self.assertEqual(undone["undone"], ["telegram"])
            self.assertFalse(tg_pal.exists())
            self.assertFalse(ayu_pal.exists())


if __name__ == "__main__":
    unittest.main()
