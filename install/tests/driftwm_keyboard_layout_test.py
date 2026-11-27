#!/usr/bin/env python3
"""Regression tests for DriftWM keyboard layout sync in DriftState and KeyboardLayout."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SYSTEM_DIR = REPO_ROOT / "src/quickshell/singletons/system"


class TestDriftWmKeyboardLayout(unittest.TestCase):
    def test_driftwm_layout_never_lags_by_one_switch(self):
        qml_bin = shutil.which("qml6") or shutil.which("qml")
        if not qml_bin:
            self.skipTest("qml6 runtime not available")

        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)

            # Minimal QML stubs so production DriftState.qml & KeyboardLayout.qml run under qml6.
            qs_dir = tmp / "imports/Quickshell"
            (qs_dir / "Io").mkdir(parents=True)
            (qs_dir / "Hyprland").mkdir(parents=True)

            (qs_dir / "qmldir").write_text(
                "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\nSingleton 1.0 Singleton.qml\n",
                encoding="utf-8",
            )
            (qs_dir / "Quickshell.qml").write_text(
                "pragma Singleton\nimport QtQuick\nItem {\n    function execDetached(cmd) {}\n    function env(k) { return ''; }\n}\n",
                encoding="utf-8",
            )
            (qs_dir / "Singleton.qml").write_text(
                "import QtQuick\nItem {}\n",
                encoding="utf-8",
            )
            (qs_dir / "Io/qmldir").write_text(
                "module Quickshell.Io\nProcess 1.0 Process.qml\nSplitParser 1.0 SplitParser.qml\nStdioCollector 1.0 StdioCollector.qml\n",
                encoding="utf-8",
            )
            (qs_dir / "Io/Process.qml").write_text(
                "import QtQuick\nItem { property bool running: false; property var command: []; property var stdout: null; property var environment: ({}); signal exited(int code, int status) }\n",
                encoding="utf-8",
            )
            (qs_dir / "Io/SplitParser.qml").write_text(
                "import QtQuick\nQtObject { property string splitMarker: '\\n'; signal read(string data) }\n",
                encoding="utf-8",
            )
            (qs_dir / "Io/StdioCollector.qml").write_text(
                "import QtQuick\nQtObject { property string text: ''; signal streamFinished() }\n",
                encoding="utf-8",
            )
            (qs_dir / "Hyprland/qmldir").write_text("module Quickshell.Hyprland\nsingleton Hyprland 1.0 Hyprland.qml\n", encoding="utf-8")
            (qs_dir / "Hyprland/Hyprland.qml").write_text(
                "pragma Singleton\nimport QtQuick\nItem { signal rawEvent(var event) }\n",
                encoding="utf-8",
            )

            # Root module at tmp/app/ mimicking src/quickshell/ parent import ("../../").
            app_dir = tmp / "app"
            sys_out = app_dir / "singletons/system"
            sys_out.mkdir(parents=True)

            for name in ("CompositorStateBase.qml", "DriftState.qml", "KeyboardLayout.qml"):
                shutil.copy(SYSTEM_DIR / name, sys_out / name)

            (app_dir / "qmldir").write_text(
                "\n".join([
                    "singleton Compositor 1.0 Compositor.qml",
                    "singleton DriftState 1.0 singletons/system/DriftState.qml",
                    "singleton KeyboardLayout 1.0 singletons/system/KeyboardLayout.qml",
                    "singleton NiriState 1.0 DummyState.qml",
                    "singleton SwayState 1.0 DummyState.qml",
                    "singleton MangoState 1.0 DummyState.qml",
                    "singleton UmbrielState 1.0 DummyState.qml",
                ]) + "\n",
                encoding="utf-8",
            )
            (app_dir / "Compositor.qml").write_text(
                "pragma Singleton\nimport QtQuick\nQtObject { readonly property string name: 'driftwm' }\n",
                encoding="utf-8",
            )
            (app_dir / "DummyState.qml").write_text(
                "pragma Singleton\nimport QtQuick\nItem {\n    property string keyboardLayout: ''\n    property string shortKeyboardLayout: 'US'\n    property bool keyboardReady: false\n    function subscribe() {}\n    function unsubscribe() {}\n    function subscribeKeyboard() {}\n    function unsubscribeKeyboard() {}\n}\n",
                encoding="utf-8",
            )

            harness = app_dir / "test_harness.qml"
            harness.write_text(
                """import QtQuick
import "."

Item {
    function assertEq(label, got, want) {
        if (got !== want) {
            console.error(label + ": expected '" + want + "', got '" + got + "'");
            Qt.exit(1);
        }
    }

    Component.onCompleted: {
        KeyboardLayout.subscribe();

        // Initial Russian state should resolve immediately on keyboardReady.
        DriftState.handleDriftState({ layout: "Russian", layout_short: "ru" });
        assertEq("init.layout", KeyboardLayout.layout, "RU");
        assertEq("init.full", KeyboardLayout.fullLayout, "Russian");

        // Switching RU -> EN must not read stale Russian keyboardLayout.
        DriftState.handleDriftState({ layout: "English (US)", layout_short: "us" });
        assertEq("to_en.layout", KeyboardLayout.layout, "EN");
        assertEq("to_en.full", KeyboardLayout.fullLayout, "English (US)");

        // Switching EN -> RU must update immediately to RU.
        DriftState.handleDriftState({ layout: "Russian", layout_short: "ru" });
        assertEq("to_ru.layout", KeyboardLayout.layout, "RU");
        assertEq("to_ru.full", KeyboardLayout.fullLayout, "Russian");

        // Same short code variant change must still update fullLayout.
        DriftState.handleDriftState({ layout: "English (US)", layout_short: "us" });
        DriftState.handleDriftState({ layout: "English (Colemak)", layout_short: "us" });
        assertEq("variant.layout", KeyboardLayout.layout, "EN");
        assertEq("variant.full", KeyboardLayout.fullLayout, "English (Colemak)");

        // Short-only payload fallback.
        DriftState.handleDriftState({ layout_short: "ru" });
        assertEq("short_only.layout", KeyboardLayout.layout, "RU");
        assertEq("short_only.full", KeyboardLayout.fullLayout, "RU");

        KeyboardLayout.unsubscribe();
        Qt.exit(0);
    }
}
""",
                encoding="utf-8",
            )

            proc = subprocess.run(
                [qml_bin, "-I", str(tmp / "imports"), "-I", str(app_dir), str(harness)],
                env={"QT_QPA_PLATFORM": "offscreen", "PATH": "/usr/bin:/bin"},
                capture_output=True,
                text=True,
                timeout=15,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


if __name__ == "__main__":
    unittest.main()
