#!/usr/bin/env python3
"""Tests for Spotify (Spicetify) theming without touching system Spotify files."""

import contextlib
import importlib.util
import json
import os
import stat
import sys
import tempfile
import time
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


class TestSpicetifyTheme(unittest.TestCase):
    @contextlib.contextmanager
    def _sandbox(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            home = tmp / "home"
            cfg = home / ".config"
            cache = home / ".cache"
            state = home / ".local" / "state" / "serpantinum"
            data_home = home / ".local" / "share"
            spicetify_bin_dir = home / ".spicetify"
            (cfg / "serpantinum").mkdir(parents=True)
            (cfg / "spicetify").mkdir(parents=True)
            (state / "matugen").mkdir(parents=True)
            cache.mkdir(parents=True)
            data_home.mkdir(parents=True)
            spicetify_bin_dir.mkdir(parents=True)

            log_file = tmp / "spicetify_calls.log"
            sp_bin = spicetify_bin_dir / "spicetify"
            sp_bin.write_text(
                f"#!/usr/bin/env bash\necho \"$*\" >> {json.dumps(str(log_file))}\n",
                encoding="utf-8",
            )
            sp_bin.chmod(0o755)

            palette = {
                "surface": "#14140c",
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
                "secondary_container": "#4a482c",
                "shadow": "#000000",
                "error": "#ffb4ab",
            }
            palette_doc = {
                "colors": {
                    k: {"default": {"hex": v, "hex_stripped": v.lstrip("#")}}
                    for k, v in palette.items()
                }
            }
            (state / "matugen/palette.json").write_text(json.dumps(palette_doc), encoding="utf-8")
            (cfg / "serpantinum/settings.json").write_text(
                json.dumps({"theme": {"mode": "dark", "apps": ["spicetify"]}}),
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
                # Exclude ~/.spicetify from PATH to verify EXTRA_BIN_DIRS discovers it
                os.environ["PATH"] = "/usr/bin:/bin"
                apptheme_mod._PATH_CACHE.clear()
                yield home, cfg, log_file
            finally:
                os.environ.clear()
                os.environ.update(old_env)
                apptheme_mod._PATH_CACHE.clear()

    def _wait_for_log(self, log_file: Path, needle: str, timeout: float = 2.0) -> str:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if log_file.is_file():
                text = log_file.read_text(encoding="utf-8")
                if needle in text:
                    return text
            time.sleep(0.05)
        return log_file.read_text(encoding="utf-8") if log_file.is_file() else ""

    def test_detect_apply_and_undo_with_user_copy(self):
        with self._sandbox() as (home, cfg, log_file):
            user_spotify = home / ".local/share/spotify"
            (user_spotify / "Apps").mkdir(parents=True)
            ini_path = cfg / "spicetify/config-xpui.ini"
            ini_path.write_text(
                f"[Setting]\n"
                f"spotify_path = {user_spotify}/\n"
                f"prefs_path = {cfg}/spotify/prefs\n"
                f"current_theme = marketplace\n"
                f"color_scheme = \n"
                f"inject_css = 1\n"
                f"replace_colors = 1\n\n"
                f"[AdditionalOptions]\n"
                f"custom_apps = marketplace\n\n"
                f"[Backup]\n"
                f"version = 1.3.8.620.g39b276d5d7ac\n",
                encoding="utf-8",
            )

            ctx = apptheme_mod.Context()
            listing = apptheme_mod.list_apps(ctx)
            entry = next((a for a in listing["apps"] if a["id"] == "spicetify"), None)
            self.assertIsNotNone(entry)
            self.assertEqual(entry["name"], "Spotify (Spicetify)")
            self.assertTrue(entry["installed"])
            self.assertEqual(entry["error"], "")

            res = apptheme_mod.apply(ctx, only=["spicetify"])
            self.assertTrue(res["ok"], res)
            self.assertTrue((cfg / "spicetify/Themes/Serpantinum/color.ini").is_file())
            self.assertTrue((cfg / "spicetify/Themes/Serpantinum/user.css").is_file())
            ini_text = ini_path.read_text(encoding="utf-8")
            self.assertIn("current_theme = Serpantinum", ini_text)
            self.assertIn("color_scheme = Serpantinum", ini_text)
            self.assertIn("custom_apps = marketplace", ini_text)
            self.assertIn(f"spotify_path = {user_spotify}/", ini_text)

            calls = self._wait_for_log(log_file, "apply -q -n")
            self.assertIn("apply -q -n", calls)

            undone = apptheme_mod.undo(ctx, ["spicetify"])
            self.assertEqual(undone["undone"], ["spicetify"])
            restored_ini = ini_path.read_text(encoding="utf-8")
            self.assertIn("current_theme = marketplace", restored_ini)
            self.assertFalse((cfg / "spicetify/Themes/Serpantinum/color.ini").exists())

    def test_reload_skips_readonly_spotify_path(self):
        with self._sandbox() as (home, cfg, log_file):
            ro_spotify = home / "ro_spotify"
            ro_apps = ro_spotify / "Apps"
            ro_apps.mkdir(parents=True)
            ro_apps.chmod(0o555)
            try:
                ini_path = cfg / "spicetify/config-xpui.ini"
                ini_path.write_text(
                    f"[Setting]\n"
                    f"spotify_path = {ro_spotify}\n"
                    f"current_theme = marketplace\n"
                    f"color_scheme = \n\n"
                    f"[Backup]\n"
                    f"version = 1.3.8.620.g39b276d5d7ac\n",
                    encoding="utf-8",
                )
                ctx = apptheme_mod.Context()
                res = apptheme_mod.apply(ctx, only=["spicetify"])
                self.assertTrue(res["ok"], res)
                time.sleep(0.3)
                calls = log_file.read_text(encoding="utf-8") if log_file.is_file() else ""
                self.assertEqual(calls, "")
            finally:
                ro_apps.chmod(stat.S_IRWXU)


if __name__ == "__main__":
    unittest.main()
