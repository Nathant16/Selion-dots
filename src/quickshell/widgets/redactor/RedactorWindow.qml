import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../"

PanelWindow {
    id: win
    color: "transparent"

    required property var host

    property alias redactorMode: redactorWorkspace
    property alias activeWidgetsModel: redactorWorkspace.activeWidgetsModel

    property string monitorName: {
        if (host.targetMonitorName && host.targetMonitorName !== "") {
            return host.targetMonitorName;
        }
        let envMon = Quickshell.env("QS_WIDGET_MONITOR");
        if (envMon && envMon.trim() !== "") return envMon.trim();
        return (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
    }

    property var targetScreen: Compositor.screenByName(win.monitorName) || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    readonly property string safeMonitorName: (monitorName || (targetScreen ? targetScreen.name : "default")).replace(/[^a-zA-Z0-9_-]/g, "_")
    screen: win.targetScreen

    WlrLayershell.namespace: "qs-widget-redactor-" + win.safeMonitorName
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Compositor.interactiveKeyboardFocus

    exclusionMode: ExclusionMode.Ignore
    focusable: true

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true

    margins.left: 0
    margins.top: 0

    function s(val) { return Scaler.s(val); }

    Timer {
        id: exitTimer
        interval: 100
        repeat: false
        onTriggered: host.close()
    }

    function exitRedactor() {
        redactorWorkspace.selectedId = "";
        host.targetSelectedWidgetId = "";
        WidgetSync.setRedactMode(win.safeMonitorName, false);
        exitTimer.start();
    }

    Component.onDestruction: {
        redactorWorkspace.selectedId = "";
        host.targetSelectedWidgetId = "";
        WidgetSync.setRedactMode(win.safeMonitorName, false);
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (redactorWorkspace.toolbar.dismiss()) return;
            redactorWorkspace.selectedId = "";
            win.exitRedactor();
        }
    }

    Shortcut {
        sequence: "Ctrl+Z"
        onActivated: redactorWorkspace.undo()
    }

    Shortcut {
        sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]
        onActivated: redactorWorkspace.redo()
    }

    Shortcut {
        sequence: "Left"
        enabled: redactorWorkspace.canNudge
        onActivated: redactorWorkspace.nudgeSelected(-1, 0, false)
    }

    Shortcut {
        sequence: "Right"
        enabled: redactorWorkspace.canNudge
        onActivated: redactorWorkspace.nudgeSelected(1, 0, false)
    }

    Shortcut {
        sequence: "Up"
        enabled: redactorWorkspace.canNudge
        onActivated: redactorWorkspace.nudgeSelected(0, -1, false)
    }

    Shortcut {
        sequence: "Down"
        enabled: redactorWorkspace.canNudge
        onActivated: redactorWorkspace.nudgeSelected(0, 1, false)
    }

    Shortcut {
        sequence: "Shift+Left"
        enabled: redactorWorkspace.canNudge
        onActivated: redactorWorkspace.nudgeSelected(-1, 0, true)
    }

    Shortcut {
        sequence: "Shift+Right"
        enabled: redactorWorkspace.canNudge
        onActivated: redactorWorkspace.nudgeSelected(1, 0, true)
    }

    Shortcut {
        sequence: "Shift+Up"
        enabled: redactorWorkspace.canNudge
        onActivated: redactorWorkspace.nudgeSelected(0, -1, true)
    }

    Shortcut {
        sequence: "Shift+Down"
        enabled: redactorWorkspace.canNudge
        onActivated: redactorWorkspace.nudgeSelected(0, 1, true)
    }

    RedactorWorkspace {
        id: redactorWorkspace
        host: win.host
        redactorWindow: win
    }
}
