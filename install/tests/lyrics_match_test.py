#!/usr/bin/env python3
"""Tests for LyricsMatch.js fullwidth punctuation normalization in Qt6."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LYRICS_MATCH_JS = REPO_ROOT / "src/quickshell/singletons/audio/LyricsMatch.js"
LYRICS_QML = REPO_ROOT / "src/quickshell/singletons/audio/Lyrics.qml"


class TestLyricsNormalization(unittest.TestCase):
    def test_fullwidth_punctuation_normalized_via_qml6(self):
        qml_bin = shutil.which("qml6") or shutil.which("qml")
        if not qml_bin:
            self.skipTest("qml6 runtime not available")

        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            shutil.copy(LYRICS_MATCH_JS, tmp / "LyricsMatch.js")
            harness = tmp / "check.qml"
            harness.write_text(
                """import QtQuick
import "LyricsMatch.js" as LM

Item {
    Component.onCompleted: {
        var sample = [
            {
                time: 20.86,
                text: "Sh!t better get played in a palace （Word）",
                words: [
                    { time: 22.3, endTime: 22.55, text: "（" },
                    { time: 22.3, endTime: 22.45, text: "Word" },
                    { time: 22.45, endTime: 22.48, text: "）" }
                ]
            },
            {
                time: 25.51,
                text: "Bald （Ha）　I look like Ray Allen （Real）【Chorus】！？：",
                words: []
            }
        ];
        var out = LM.normalizeLyricsList(sample);
        if (out[0].text !== "Sh!t better get played in a palace (Word)") {
            console.error("BAD_LINE_0:" + out[0].text);
            Qt.exit(1);
        }
        if (out[0].words[0].text !== "(" || out[0].words[1].text !== "Word" || out[0].words[2].text !== ")") {
            console.error("BAD_WORDS:" + JSON.stringify(out[0].words));
            Qt.exit(1);
        }
        if (out[1].text !== "Bald (Ha) I look like Ray Allen (Real)[Chorus]!?:") {
            console.error("BAD_LINE_1:" + out[1].text);
            Qt.exit(1);
        }
        if (LM.cleanString("Track （feat. Artist）") !== "Track") {
            console.error("BAD_CLEAN:" + LM.cleanString("Track （feat. Artist）"));
            Qt.exit(1);
        }
        Qt.exit(0);
    }
}
""",
                encoding="utf-8",
            )
            proc = subprocess.run(
                [qml_bin, str(harness)],
                env={"QT_QPA_PLATFORM": "offscreen", "PATH": "/usr/bin:/bin"},
                capture_output=True,
                text=True,
                timeout=15,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_lyrics_qml_renders_no_space_after_open_paren(self):
        src = LYRICS_QML.read_text(encoding="utf-8")
        self.assertIn("normalizeLyricsList", src)
        self.assertIn(r"/[\(\[\u201C\u2018]$/", src)


if __name__ == "__main__":
    unittest.main()
