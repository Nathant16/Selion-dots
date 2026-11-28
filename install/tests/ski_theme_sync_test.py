#!/usr/bin/env python3
"""Tests for race-free Ski settings.json opacity syncing and preservation."""

import concurrent.futures
import contextlib
import importlib.util
import json
import os
import sys
import tempfile
import threading
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


class TestSkiThemeSync(unittest.TestCase):
    @contextlib.contextmanager
    def _sandbox(self, initial_settings: dict[str, Any] | str):
        env_keys = ("HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "QS_STATE_DIR")
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            home = tmp_path / "home"
            cfg = tmp_path / "xdg_config"
            state = tmp_path / "xdg_state" / "serpantinum"
            (home / ".config" / "ski").mkdir(parents=True)
            (cfg / "ski").mkdir(parents=True)
            (state / "matugen").mkdir(parents=True)

            ski_cfg = cfg / "ski" / "settings.json"
            if isinstance(initial_settings, str):
                ski_cfg.write_text(initial_settings, encoding="utf-8")
            else:
                ski_cfg.write_text(
                    json.dumps(initial_settings, indent=2, ensure_ascii=False),
                    encoding="utf-8",
                )

            old_env = {k: os.environ.get(k) for k in env_keys}
            try:
                os.environ["HOME"] = str(home)
                os.environ["XDG_CONFIG_HOME"] = str(cfg)
                os.environ["XDG_STATE_HOME"] = str(tmp_path / "xdg_state")
                os.environ["QS_STATE_DIR"] = str(state)
                yield home, cfg, state, ski_cfg
            finally:
                for k, v in old_env.items():
                    if v is None:
                        os.environ.pop(k, None)
                    else:
                        os.environ[k] = v

    def test_concurrent_sync_and_continuous_reader_preserve_user_settings(self):
        user_settings = {
            "theme": "Serpantinum",
            "language": "ru",
            "opacity": 77,
            "view_mode": "Grid",
            "grid_size": 96,
            "show_hidden": True,
            "vim_keys": True,
            "single_click_open": True,
            "last_dir": "/home/Nathant/Загрузки/Проекты",
            "session_tabs": ["/home/Nathant/Музыка", "/media/Drives/Projects"],
            "folder_views": {"/home/Nathant/Загрузки": {"view_mode": "Grid"}},
            "keybinds": {"toggle_hidden": "h"},
            "plugins": {"demo": {"enabled": True}},
        }

        with self._sandbox(user_settings) as (_home, _cfg, state, ski_cfg):
            stop_flag = threading.Event()
            read_errors: list[str] = []
            read_count = 0

            def watch_reader():
                nonlocal read_count
                while not stop_flag.is_set():
                    try:
                        text = ski_cfg.read_text(encoding="utf-8")
                        parsed = json.loads(text)
                        read_count += 1
                        if not isinstance(parsed, dict) or parsed.get("vim_keys") is not True:
                            read_errors.append(f"unexpected payload: {text!r}")
                    except Exception as exc:
                        read_errors.append(f"{type(exc).__name__}: {exc}")

            reader_thread = threading.Thread(target=watch_reader, daemon=True)
            reader_thread.start()
            try:
                with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
                    futures = [
                        pool.submit(
                            sync_mod.sync_apps,
                            0.85,
                            65 + (i % 3) * 10,
                            True,
                            True,
                            state,
                        )
                        for i in range(30)
                    ]
                    for fut in futures:
                        fut.result()
            finally:
                stop_flag.set()
                reader_thread.join(timeout=2.0)

            self.assertGreater(read_count, 0)
            self.assertEqual(read_errors, [])

            final_data = json.loads(ski_cfg.read_text(encoding="utf-8"))
            for k, v in user_settings.items():
                if k == "opacity":
                    self.assertIn(final_data[k], (65, 75, 85))
                else:
                    self.assertEqual(final_data[k], v)

    def test_idempotent_sync_skips_rewrite_when_opacity_matches(self):
        with self._sandbox({"opacity": 77, "vim_keys": True, "view_mode": "Grid"}) as (_home, _cfg, state, ski_cfg):
            before = ski_cfg.stat()
            before_bytes = ski_cfg.read_bytes()

            sync_mod.sync_apps(0.77, 77, True, True, state)
            sync_mod.sync_apps(0.77, 77, True, True, state)

            after = ski_cfg.stat()
            self.assertEqual(after.st_ino, before.st_ino)
            self.assertEqual(after.st_mtime_ns, before.st_mtime_ns)
            self.assertEqual(ski_cfg.read_bytes(), before_bytes)

            # Updating opacity to a new value performs an atomic replacement
            sync_mod.sync_apps(0.90, 90, True, True, state)
            updated = json.loads(ski_cfg.read_text(encoding="utf-8"))
            self.assertEqual(updated["opacity"], 90)
            self.assertTrue(updated["vim_keys"])
            self.assertEqual(updated["view_mode"], "Grid")

    def test_respects_xdg_config_home_and_ignores_corrupt_json(self):
        with self._sandbox("{not-valid-json") as (home, _cfg, state, ski_cfg):
            home_ski = home / ".config" / "ski" / "settings.json"
            home_ski.write_text('{"opacity": 77, "show_hidden": false}\n', encoding="utf-8")

            sync_mod.sync_apps(0.90, 90, True, True, state)

            self.assertEqual(ski_cfg.read_text(encoding="utf-8"), "{not-valid-json")
            self.assertEqual(json.loads(home_ski.read_text(encoding="utf-8"))["opacity"], 77)


if __name__ == "__main__":
    unittest.main()
