#!/usr/bin/env python3
"""Tests for race-free kitty.conf syncing and integration preservation."""

import concurrent.futures
import contextlib
import importlib.util
import json
import os
import shutil
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
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


sync_mod = _load_mod("sync_compositor_theme", "src/scripts/theming/sync_compositor_theme.py")
apptheme_mod = _load_mod("apptheme", "src/scripts/theming/apptheme.py")


class TestKittyThemeSync(unittest.TestCase):
    def _setup_sandbox(self, tmp: Path) -> tuple[Path, Path, Path, Path]:
        home = tmp / "home"
        cfg = home / ".config"
        state = home / ".local" / "state" / "serpantinum"
        bin_dir = tmp / "bin"
        (cfg / "kitty").mkdir(parents=True)
        (cfg / "serpantinum").mkdir(parents=True)
        (state / "matugen").mkdir(parents=True)
        bin_dir.mkdir(parents=True)

        shutil.copy(REPO_ROOT / "config/kitty/kitty.conf", cfg / "kitty/kitty.conf")
        (cfg / "serpantinum/settings.json").write_text(
            json.dumps({"theme": {"elementOpacity": 50, "blurBackground": True, "applyEffectsToWindows": True}}),
            encoding="utf-8",
        )

        colors = {
            "surface_container": "#212018",
            "on_surface": "#e6e2d5",
            "on_secondary_container": "#e8e4be",
            "secondary_container": "#4a482c",
            "primary": "#cfca74",
            "on_primary": "#343200",
            "tertiary": "#a5d0bb",
            "surface_variant": "#49473a",
            "error": "#ffb4ab",
            "on_primary_container": "#ece68d",
            "primary_container": "#4c4900",
            "on_surface_variant": "#cac7b5",
            "surface": "#14140c",
            "on_secondary": "#333118",
            "secondary": "#ccc8a4",
            "on_tertiary": "#0d3728",
            "tertiary_container": "#264e3e",
            "outline": "#949181",
            "error_container": "#93000a",
            "primary_fixed": "#ece68d",
            "tertiary_fixed": "#c0ecd6",
            "secondary_fixed": "#e8e4be",
            "inverse_primary": "#646116",
        }
        palette = {
            "colors": {
                k: {"default": {"hex": v}, "dark": {"hex": v}, "light": {"hex": v}}
                for k, v in colors.items()
            }
        }
        (state / "matugen/palette.json").write_text(json.dumps(palette), encoding="utf-8")

        fake_pkill = bin_dir / "pkill"
        fake_pkill.write_text("#!/usr/bin/env bash\necho \"$*\" >> \"$HOME/pkill.log\"\nexit 0\n", encoding="utf-8")
        fake_pkill.chmod(0o755)
        fake_matugen = bin_dir / "matugen"
        fake_matugen.write_text(
            "#!/usr/bin/env python3\n"
            "import json, pathlib, re, sys\n"
            "cfg = pathlib.Path(sys.argv[sys.argv.index('-c') + 1]).read_text()\n"
            "pal = json.loads(pathlib.Path(sys.argv[sys.argv.index('json') + 1]).read_text())\n"
            "for inp, out in zip(re.findall(r'input_path = \"([^\"]+)\"', cfg), re.findall(r'output_path = \"([^\"]+)\"', cfg)):\n"
            "    txt = pathlib.Path(inp).read_text()\n"
            "    for k, v in pal['colors'].items():\n"
            "        txt = txt.replace('{{colors.' + k + '.default.hex}}', v['default']['hex'])\n"
            "    pathlib.Path(out).parent.mkdir(parents=True, exist_ok=True)\n"
            "    pathlib.Path(out).write_text(txt)\n",
            encoding="utf-8",
        )
        fake_matugen.chmod(0o755)
        return home, cfg, state, bin_dir

    @contextlib.contextmanager
    def _sandbox(self):
        env_keys = (
            "HOME",
            "XDG_CONFIG_HOME",
            "XDG_STATE_HOME",
            "XDG_DATA_HOME",
            "XDG_CACHE_HOME",
            "QS_STATE_DIR",
            "QS_SETTINGS",
            "SERPANTINUM_APPTHEME_BUILTIN",
            "PATH",
        )
        with tempfile.TemporaryDirectory() as tmp:
            home, cfg, state, bin_dir = self._setup_sandbox(Path(tmp))
            old_env = {k: os.environ.get(k) for k in env_keys}
            try:
                os.environ["HOME"] = str(home)
                os.environ["XDG_CONFIG_HOME"] = str(cfg)
                os.environ["XDG_STATE_HOME"] = str(home / ".local" / "state")
                os.environ["XDG_DATA_HOME"] = str(home / ".local" / "share")
                os.environ["XDG_CACHE_HOME"] = str(home / ".cache")
                os.environ["QS_STATE_DIR"] = str(state)
                os.environ["QS_SETTINGS"] = str(cfg / "serpantinum/settings.json")
                os.environ["SERPANTINUM_APPTHEME_BUILTIN"] = str(REPO_ROOT / "src/assets/matugen/apps")
                os.environ["PATH"] = f"{bin_dir}:{old_env['PATH']}"
                yield home, cfg, state
            finally:
                for k, v in old_env.items():
                    if v is None:
                        os.environ.pop(k, None)
                    else:
                        os.environ[k] = v

    def test_concurrent_sync_and_missing_include_repair(self):
        with self._sandbox() as (home, cfg, state):
            ctx = apptheme_mod.Context()

            # Run apptheme and sync_apps concurrently many times to stress-test locking & atomic writes
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                futures = [pool.submit(apptheme_mod.apply, ctx, enabled_override=["kitty"], only=["kitty"]) for _ in range(4)]
                futures += [pool.submit(sync_mod.sync_apps, 0.83, 83, True, True, state) for _ in range(8)]
                for fut in futures:
                    fut.result()

            kitty_text = (cfg / "kitty/kitty.conf").read_text(encoding="utf-8")
            self.assertIn("font_size        15.0", kitty_text)
            self.assertIn("JetBrainsMono Nerd Font", kitty_text)
            self.assertIn("background_opacity 1.0", kitty_text)
            self.assertIn("background_blur 1", kitty_text)
            self.assertIn("include themes/serpantinum.conf", kitty_text)
            self.assertTrue((cfg / "kitty/themes/serpantinum.conf").is_file())
            self.assertIn("#212018", (cfg / "kitty/themes/serpantinum.conf").read_text(encoding="utf-8"))

            # Simulate kitty.conf being overwritten without include line while themes/serpantinum.conf remains intact
            shutil.copy(REPO_ROOT / "config/kitty/kitty.conf", cfg / "kitty/kitty.conf")
            res = apptheme_mod.apply(ctx, enabled_override=["kitty"], only=["kitty"])
            self.assertTrue(res["ok"])
            self.assertTrue(res["apps"]["kitty"]["changed"])
            repaired = (cfg / "kitty/kitty.conf").read_text(encoding="utf-8")
            self.assertIn("include themes/serpantinum.conf", repaired)

            # First sync_apps restores opacity/blur after kitty.conf overwrite; wait for detached reload_app child
            sync_mod.sync_apps(0.83, 83, True, True, state)
            repaired_full = (cfg / "kitty/kitty.conf").read_text(encoding="utf-8")
            self.assertIn("background_opacity 1.0", repaired_full)
            self.assertIn("background_blur 1", repaired_full)
            self.assertIn("include themes/serpantinum.conf", repaired_full)
            time.sleep(0.3)

            # Idempotent sync_apps must not signal kitty when nothing changed
            log_file = home / "pkill.log"
            if log_file.exists():
                log_file.unlink()
            sync_mod.sync_apps(0.83, 83, True, True, state)
            sync_mod.sync_apps(0.83, 83, True, True, state)
            self.assertFalse(log_file.exists())

    def test_sync_apps_signals_only_when_kitty_conf_changes(self):
        with self._sandbox() as (home, _cfg, state):
            log_file = home / "pkill.log"
            sync_mod.sync_apps(0.83, 83, True, True, state)
            self.assertTrue(log_file.exists())
            self.assertEqual(len(log_file.read_text(encoding="utf-8").splitlines()), 1)

            log_file.unlink()
            sync_mod.sync_apps(0.83, 83, True, True, state)
            sync_mod.sync_apps(0.83, 83, True, True, state)
            self.assertFalse(log_file.exists())


if __name__ == "__main__":
    unittest.main()
