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
    property int minimapSubscribers: 0

    property real cameraX: 0
    property real cameraY: 0
    property real zoom: 1.0
    property real screenWidth: 1920
    property real screenHeight: 1080
    property var bookmarks: ({ "1": [0, 0], "2": [2500, 0], "3": [5000, 0], "4": [7500, 0], "5": [10000, 0], "6": [12500, 0], "7": [15000, 0], "8": [17500, 0], "9": [20000, 0] })
    property int bookmarksRevision: 0

    signal bookmarksUpdated()
    signal cameraMoved(real cx, real cy, real zoom)

    readonly property bool needsWatch: Compositor.name === "driftwm" && (workspaceSubscribers + windowSubscribers + keyboardSubscribers + minimapSubscribers) > 0

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

    function subscribeMinimap() {
        minimapSubscribers++;
    }

    function unsubscribeMinimap() {
        minimapSubscribers = Math.max(0, minimapSubscribers - 1);
    }

    function focusWorkspace(index) {
        Quickshell.execDetached(["driftwm", "msg", "action", "go-to-bookmark", String(index + 1)]);
    }

    function setCamera(x, y) {
        Quickshell.execDetached(["driftwm", "msg", "camera", String(Math.round(x)), String(Math.round(y))]);
    }

    function setZoom(level) {
        let clamped = Math.max(0.1, Math.min(1.0, level));
        Quickshell.execDetached(["driftwm", "msg", "zoom", clamped.toFixed(2)]);
    }

    function zoomIn() {
        Quickshell.execDetached(["driftwm", "msg", "action", "zoom-in"]);
    }

    function zoomOut() {
        Quickshell.execDetached(["driftwm", "msg", "action", "zoom-out"]);
    }

    function zoomReset() {
        Quickshell.execDetached(["driftwm", "msg", "action", "zoom-reset"]);
    }

    function zoomToFit() {
        Quickshell.execDetached(["driftwm", "msg", "action", "zoom-to-fit"]);
    }

    function moveWindowToWorkspace(index) {
        Quickshell.execDetached(["driftwm", "msg", "action", "move-to-bookmark", String(index + 1)]);
    }

    function moveWindow(id, x, y) {
        if (id === undefined || id === null) return;
        Quickshell.execDetached(["driftwm", "msg", "move", "--id", String(id), String(Math.round(x)), String(Math.round(y))]);
    }

    function focusWindow(id) {
        if (id === undefined || id === null) return;
        Quickshell.execDetached(["driftwm", "msg", "focus", "--id", String(id)]);
    }

    function relaunchWindow(id) {
        if (id === undefined || id === null) return;
        Quickshell.execDetached(["driftwm", "msg", "relaunch", "--id", String(id)]);
    }

    function closeWindow(id) {
        if (id === undefined || id === null) return;
        Quickshell.execDetached(["driftwm", "msg", "close", "--id", String(id)]);
    }

    function switchLayout() {
        Quickshell.execDetached(["driftwm", "msg", "action", "switch-layout", "next"]);
    }

    property real lastBookmarkInitAt: 0

    function linearBookmarks() {
        let bms = ({});
        for (let i = 1; i <= 9; i++) bms[String(i)] = [(i - 1) * 2500, 0];
        return bms;
    }

    function initBookmarks() {
        // Throttle writes so a failing direct call cannot spawn a process storm
        // through the periodic refresh timer.
        let now = Date.now();
        if (now - lastBookmarkInitAt < 2000) return;
        lastBookmarkInitAt = now;

        // Update the local copy immediately so the minimap and the bar snap to
        // the linear layout while the compositor commands are in flight.
        root.bookmarks = linearBookmarks();
        root.bookmarksRevision++;
        root.bookmarksUpdated();

        let script = "for i in 1 2 3 4 5 6 7 8 9; do driftwm msg bookmark \$i \$(( (i-1)*2500 )) 0 >/dev/null 2>&1; done";
        Quickshell.execDetached(["sh", "-c", script]);
        bookmarkRefreshTimer.restart();
    }

    function handleDriftState(state) {
        if (!state) return;

        // 1. Workspaces / Bookmarks
        let curBookmark = state.active_bookmark;
        let actIdx = 0;
        let bms = root.bookmarks;
        if (curBookmark !== null && curBookmark !== undefined) {
            let parsed = parseInt(curBookmark);
            if (!isNaN(parsed) && parsed >= 1 && parsed <= 9) {
                actIdx = parsed - 1;
            }
        } else if (state.camera && Array.isArray(state.camera)) {
            let cx = Number(state.camera[0]) || 0;
            let cy = Number(state.camera[1]) || 0;
            let bestDist = Infinity;
            let bestIdx = 0;
            for (let i = 1; i <= 9; i++) {
                let key = String(i);
                let bx = (bms && bms[key] && Array.isArray(bms[key])) ? (Number(bms[key][0]) || 0) : ((i - 1) * 2500);
                let by = (bms && bms[key] && Array.isArray(bms[key])) ? (Number(bms[key][1]) || 0) : 0;
                let d = Math.hypot(cx - bx, cy - by);
                if (d < bestDist) {
                    bestDist = d;
                    bestIdx = i - 1;
                }
            }
            actIdx = bestIdx;
        }
        if (root.activeIndex !== actIdx) {
            root.activeIndex = actIdx;
            root.refreshBookmarks();
        }

        // Occupied workspaces based on window positions relative to saved bookmarks
        let rawWins = Array.isArray(state.windows) ? state.windows : [];
        let wins = [];
        let occ = {};

        for (let i = 0; i < rawWins.length; i++) {
            let w = rawWins[i];
            if (!w || w.is_widget) continue;
            wins.push(w);
            if (w.position && Array.isArray(w.position)) {
                let wx = Number(w.position[0]) || 0;
                let wy = Number(w.position[1]) || 0;
                let bestDist = Infinity;
                let bestIdx = 0;
                for (let k = 1; k <= 9; k++) {
                    let key = String(k);
                    let bx = (bms && bms[key] && Array.isArray(bms[key])) ? (Number(bms[key][0]) || 0) : ((k - 1) * 2500);
                    let by = (bms && bms[key] && Array.isArray(bms[key])) ? (Number(bms[key][1]) || 0) : 0;
                    let d = Math.hypot(wx - bx, wy - by);
                    if (d < bestDist) {
                        bestDist = d;
                        bestIdx = k - 1;
                    }
                }
                occ[bestIdx] = true;
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

        // 4. Camera, Zoom & Outputs
        let cx = root.cameraX;
        let cy = root.cameraY;
        let z = root.zoom;
        if (state.camera && Array.isArray(state.camera) && state.camera.length >= 2) {
            let scx = Number(state.camera[0]);
            let scy = Number(state.camera[1]);
            if (!isNaN(scx)) cx = scx;
            if (!isNaN(scy)) cy = scy;
        }
        if (state.zoom !== undefined && state.zoom !== null) {
            let sz = Number(state.zoom);
            if (!isNaN(sz) && sz > 0) z = sz;
        }
        if (state.outputs && Array.isArray(state.outputs) && state.outputs.length > 0) {
            let out = state.outputs[0];
            if (out.size && Array.isArray(out.size) && out.size.length >= 2) {
                root.screenWidth = Number(out.size[0]) || 1920;
                root.screenHeight = Number(out.size[1]) || 1080;
            }
            if (out.camera && Array.isArray(out.camera) && out.camera.length >= 2) {
                let ocx = Number(out.camera[0]);
                let ocy = Number(out.camera[1]);
                if (!isNaN(ocx)) cx = ocx;
                if (!isNaN(ocy)) cy = ocy;
            }
            if (out.zoom !== undefined && out.zoom !== null) {
                let oz = Number(out.zoom);
                if (!isNaN(oz) && oz > 0) z = oz;
            }
        }

        let moved = (Math.abs(cx - root.cameraX) > 0.05 || Math.abs(cy - root.cameraY) > 0.05 || Math.abs(z - root.zoom) > 0.001);
        root.cameraX = cx;
        root.cameraY = cy;
        root.zoom = z;
        if (moved) {
            root.cameraMoved(cx, cy, z);
        }
    }

    function applyBookmarkList(raw) {
        let str = raw ? String(raw).trim() : "";
        if (!str) return;
        let obj;
        try {
            obj = JSON.parse(str);
        } catch (e) {
            return;
        }
        if (!obj || !obj.Ok || !obj.Ok.Bookmarks) return;
        let bms = obj.Ok.Bookmarks;
        let broken = false;
        for (let i = 1; i <= 9; i++) {
            let expectedX = (i - 1) * 2500;
            let expectedY = 0;
            let bm = bms[String(i)];
            if (!bm || !Array.isArray(bm) || Number(bm[0]) !== expectedX || Number(bm[1]) !== expectedY) {
                broken = true;
                break;
            }
        }
        if (broken) {
            root.initBookmarks();
        } else {
            root.bookmarks = bms;
            root.bookmarksRevision++;
            root.bookmarksUpdated();
        }
    }

    Process {
        id: bookmarksProc
        command: ["driftwm", "msg", "bookmark", "--json"]
        // `driftwm msg ... --json` prints pretty-printed JSON, so the reply must
        // be collected whole. SplitParser (line-by-line) always failed here and
        // left the four-corner default bookmarks in place.
        stdout: StdioCollector {
            id: bookmarksOut
            onStreamFinished: root.applyBookmarkList(bookmarksOut.text)
        }
    }

    function refreshBookmarks() {
        if (Compositor.name === "driftwm" && !bookmarksProc.running) {
            bookmarksProc.running = true;
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

    Timer {
        id: bookmarkRefreshTimer
        interval: 300
        repeat: false
        onTriggered: refreshBookmarks()
    }

    Timer {
        id: periodicBookmarkTimer
        running: root.needsWatch && root.minimapSubscribers > 0
        interval: 1500
        repeat: true
        onTriggered: root.refreshBookmarks()
    }

    Component.onCompleted: {
        if (Compositor.name === "driftwm") {
            refreshBookmarks();
        }
    }
}
