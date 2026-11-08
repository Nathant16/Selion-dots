pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

CompositorStateBase {
    id: root

    property var windows: []
    signal windowsUpdated()

    property string keyboardLayout: ""
    property string shortKeyboardLayout: "US"
    property bool keyboardReady: false

    property int workspaceSubscribers: 0
    property int windowSubscribers: 0
    property int keyboardSubscribers: 0

    readonly property bool needsWatch: Compositor.name === "driftwm" && (workspaceSubscribers + windowSubscribers + keyboardSubscribers) > 0

    // Keep base.watching false so serpantinum-core is not executed for driftwm
    watching: false

    function subscribe() {
        workspaceSubscribers++;
    }

    function unsubscribe() {
        workspaceSubscribers = Math.max(0, workspaceSubscribers - 1);
    }

    function subscribeWindows() {
        windowSubscribers++;
    }

    function unsubscribeWindows() {
        windowSubscribers = Math.max(0, windowSubscribers - 1);
    }

    function subscribeKeyboard() {
        keyboardSubscribers++;
    }

    function unsubscribeKeyboard() {
        keyboardSubscribers = Math.max(0, keyboardSubscribers - 1);
    }

    function focusWorkspace(index) {
        Quickshell.execDetached(["driftwm", "msg", "action", "go-to-bookmark", String(index + 1)]);
    }

    function moveWindowToWorkspace(index) {
        Quickshell.execDetached(["driftwm", "msg", "action", "move-to-bookmark", String(index + 1)]);
    }

    function focusWindow(id) {
        if (id === undefined || id === null) return;
        Quickshell.execDetached(["driftwm", "msg", "focus", "--id", String(id)]);
    }

    function closeWindow(id) {
        if (id === undefined || id === null) return;
        Quickshell.execDetached(["driftwm", "msg", "close", "--id", String(id)]);
    }

    function switchLayout() {
        Quickshell.execDetached(["driftwm", "msg", "action", "switch-layout", "next"]);
    }

    function initBookmarks() {
        let script = "for i in 1 2 3 4 5 6 7 8 9; do driftwm msg bookmark \$i \$(( (i-1)*2500 )) 0 2>/dev/null; done";
        Quickshell.execDetached(["sh", "-c", script]);
    }

    function handleDriftState(state) {
        if (!state) return;

        // 1. Workspaces / Bookmarks
        let curBookmark = state.active_bookmark;
        let actIdx = 0;
        if (curBookmark !== null && curBookmark !== undefined) {
            let parsed = parseInt(curBookmark);
            if (!isNaN(parsed) && parsed >= 1 && parsed <= 9) {
                actIdx = parsed - 1;
            }
        } else if (state.camera && Array.isArray(state.camera)) {
            let cx = state.camera[0] || 0;
            actIdx = Math.max(0, Math.min(8, Math.round(cx / 2500)));
        }
        if (root.activeIndex !== actIdx) {
            root.activeIndex = actIdx;
        }

        // Occupied workspaces based on window positions
        let rawWins = Array.isArray(state.windows) ? state.windows : [];
        let wins = [];
        let occ = {};

        for (let i = 0; i < rawWins.length; i++) {
            let w = rawWins[i];
            if (!w || w.is_widget) continue;
            wins.push(w);
            if (w.position && Array.isArray(w.position)) {
                let wx = w.position[0];
                let idx = Math.max(0, Math.min(8, Math.round(wx / 2500)));
                occ[idx] = true;
            }
        }

        root.assign("occupiedMap", occ);

        // 2. Windows list
        if (root.assign("windows", wins)) {
            root.windowsUpdated();
        }

        // 3. Keyboard Layout
        if (state.layout_short !== undefined && state.layout_short !== null) {
            let kl = String(state.layout_short).trim().toUpperCase();
            if (kl !== "") {
                root.shortKeyboardLayout = kl;
                root.keyboardLayout = state.layout ? String(state.layout) : kl;
                root.keyboardReady = true;
            }
        }
    }

    Process {
        id: driftProc
        running: root.needsWatch
        command: ["driftwm", "msg", "subscribe", "--json"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                let str = data ? data.trim() : "";
                if (!str) return;
                let obj;
                try {
                    obj = JSON.parse(str);
                } catch (e) {
                    return;
                }
                if (!obj) return;
                let state = obj.State || (obj.Ok && obj.Ok.State);
                if (state) root.handleDriftState(state);
            }
        }
        onExited: {
            if (root.needsWatch) driftRestart.restart();
        }
    }

    Timer {
        id: driftRestart
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.needsWatch && !driftProc.running) driftProc.running = true;
        }
    }

    Component.onCompleted: {
        if (Compositor.name === "driftwm") {
            initBookmarks();
        }
    }
}
