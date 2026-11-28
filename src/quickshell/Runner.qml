import QtQuick
import Quickshell

Scope {
    id: runnerRoot

    property string targetFile: Quickshell.env("SERPANTINUM_TARGET_FILE") || ""

    Loader {
        active: runnerRoot.targetFile !== ""
        source: runnerRoot.targetFile
    }
}
