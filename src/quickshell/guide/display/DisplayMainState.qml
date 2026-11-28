import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "../../"

GuideTab {
    id: displayTabRoot

    property var defaultDisplaySettings: ({
        "monitors": {}
    })

    property var displaySettings: JSON.parse(JSON.stringify(Config.getSetting("display", defaultDisplaySettings)))
    property var monitorsList: DisplayCache.monitors
    property var monitorNames: {
        let names = [];
        for (let i = 0; i < monitorsList.length; i++) {
            if (monitorsList[i] && monitorsList[i].name) names.push(monitorsList[i].name);
        }
        return names;
    }
    property var monitorsByName: {
        let map = {};
        for (let i = 0; i < monitorsList.length; i++) {
            if (monitorsList[i] && monitorsList[i].name) map[monitorsList[i].name] = monitorsList[i];
        }
        return map;
    }
    readonly property int activeMonitorCount: {
        let count = 0;
        for (let i = 0; i < monitorsList.length; i++) {
            if (monitorsList[i] && monitorsList[i].active !== false) count++;
        }
        return count;
    }
    property bool animateCards: false

    readonly property string compositor: Compositor.name

    property string pendingMonName: ""
    property real pendingMonTemp: 50

    property string pendingMonScaleName: ""
    property real pendingMonScaleVal: 1.0
    property var queuedApplyCmds: []
    property string scaleLockMonitor: ""
    property double scaleLockUntilMs: 0
    property double layoutLockUntilMs: 0
    property double powerLockUntilMs: 0

    function isScaleLockedFor(monName) {
        if (!monName) return false;
        if (displayTabRoot.pendingMonScaleName === monName) return true;
        if (displayTabRoot.scaleLockMonitor === monName) {
            if (monitorApplyProc.running || displayTabRoot.queuedApplyCmds.length > 0) return true;
            if (Date.now() < displayTabRoot.scaleLockUntilMs) return true;
        }
        return false;
    }

    function logicalBoxFor(m) {
        let name = (m && m.name) ? String(m.name) : "";
        let dims = (m && m.dimensions) ? String(m.dimensions).split("x") : ["1920", "1080"];
        let rawW = parseFloat(dims[0]) || 1920;
        let rawH = parseFloat(dims[1]) || 1080;
        let tr = (m && m.transform) ? String(m.transform).toLowerCase() : "normal";
        if (tr.indexOf("90") !== -1 || tr.indexOf("270") !== -1) {
            let tmp = rawW;
            rawW = rawH;
            rawH = tmp;
        }
        let sc = (m && m.scale !== undefined && Number(m.scale) > 0) ? Number(m.scale) : 1.0;
        let logW = Math.max(1, Math.round(rawW / sc));
        let logH = Math.max(1, Math.round(rawH / sc));
        let x = (m && m.x !== undefined && m.x !== null && !isNaN(Number(m.x))) ? Math.round(Number(m.x)) : 0;
        let y = (m && m.y !== undefined && m.y !== null && !isNaN(Number(m.y))) ? Math.round(Number(m.y)) : 0;
        return {
            name: name,
            x: x,
            y: y,
            logW: logW,
            logH: logH,
            rawW: rawW,
            rawH: rawH,
            scale: sc,
            active: m ? (m.active !== false) : true,
            dimensions: (m && m.dimensions) ? String(m.dimensions) : "1920x1080",
            framerate: (m && m.framerate) ? String(m.framerate) : "60",
            transform: tr
        };
    }

    function normalizeScaleFactor(rawScale) {
        let num = Number(rawScale);
        if (isNaN(num) || num <= 0) return 1.0;
        let clampedPct = Math.max(50, Math.min(300, Math.round(num * 100)));
        return Math.round(clampedPct) / 100.0;
    }

    function syncMonitorModels(mList) {
        if (!Array.isArray(mList) || mList.length === 0) return;
        let nextNames = [];
        let nextMap = {};
        for (let i = 0; i < mList.length; i++) {
            let item = mList[i];
            if (item && item.name) {
                nextNames.push(item.name);
                nextMap[item.name] = item;
            }
        }
        displayTabRoot.monitorsList = mList;
        DisplayCache.monitors = mList;
        displayTabRoot.monitorsByName = nextMap;
        if (JSON.stringify(nextNames) !== JSON.stringify(displayTabRoot.monitorNames)) {
            displayTabRoot.monitorNames = nextNames;
        }
    }

    function refreshDisplaySettings() {
        displayTabRoot.displaySettings = JSON.parse(JSON.stringify(Config.getSetting("display", displayTabRoot.defaultDisplaySettings)));
    }

    signal scaleSettled(string monName)

    function validScalesForResolution(width, height) {
        if (!width || !height) return [1.0];

        let candidates = [];
        let seen = {};

        function tryAddScale(s, requireInteger) {
            let sRounded = Math.round(s * 10000) / 10000;
            if (sRounded < 0.5 || sRounded > 3.0) return;
            let key = sRounded.toFixed(4);
            if (seen[key]) return;

            if (requireInteger) {
                let lw = width / sRounded;
                let lh = height / sRounded;
                let epsilon = 0.05;
                if (Math.abs(lw - Math.round(lw)) >= epsilon || Math.abs(lh - Math.round(lh)) >= epsilon) {
                    return;
                }
            }

            seen[key] = true;
            candidates.push(sRounded);
        }

        // Exact Wayland 1/120 fractional scale grid cleanly dividing both width and height (used by Hyprland)
        for (let n = 60; n <= 360; n++) {
            if ((width * 120) % n === 0 && (height * 120) % n === 0) {
                tryAddScale(n / 120.0, false);
            }
        }

        for (let s = 0.50; s <= 3.001; s += 0.05) {
            tryAddScale(Math.round(s * 100) / 100, true);
        }

        candidates.sort((a, b) => a - b);
        return candidates.length > 0 ? candidates : [1.0];
    }

    function nearestValidScaleFromList(validList, target) {
        if (!validList || validList.length === 0) return 1.0;
        let best = validList[0];
        let bestDiff = Math.abs(validList[0] - target);
        for (let i = 1; i < validList.length; i++) {
            let diff = Math.abs(validList[i] - target);
            if (diff < bestDiff) {
                best = validList[i];
                bestDiff = diff;
            }
        }
        return best;
    }

    Process {
        id: monitorDetector
        running: false
        command: [
            "python3",
            Caching.serpantinumDir + "/scripts/system/monitors_detector.py"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text;
                if (!out) {
                    displayTabRoot.loadFallbackScreens();
                    return;
                }
                let mList = [];
                try {
                    let data = JSON.parse(out.trim());
                    if (Array.isArray(data)) {
                        mList = data;
                    }
                } catch (e) {
                }
                if (mList.length > 0) {
                    if (JSON.stringify(mList) !== JSON.stringify(displayTabRoot.monitorsList)) {
                        displayTabRoot.syncMonitorModels(mList);
                    }
                    displayTabRoot.refreshDisplaySettings();
                    Qt.callLater(function() { displayTabRoot.animateCards = true; });
                } else {
                    displayTabRoot.loadFallbackScreens();
                }
            }
        }
    }

    Timer {
        id: scaleLockClearTimer
        interval: 950
        repeat: false
        onTriggered: {
            let lockedMon = displayTabRoot.scaleLockMonitor;
            displayTabRoot.scaleLockMonitor = "";
            displayTabRoot.scaleLockUntilMs = 0;
            if (lockedMon !== "") {
                displayTabRoot.scaleSettled(lockedMon);
            }
        }
    }

    Process {
        id: monitorApplyProc
        running: false
        onExited: function() {
            if (displayTabRoot.queuedApplyCmds.length > 0) {
                let nextQueue = displayTabRoot.queuedApplyCmds.slice();
                let nextCmd = nextQueue.shift();
                displayTabRoot.queuedApplyCmds = nextQueue;
                monitorApplyProc.command = nextCmd;
                monitorApplyProc.running = true;
                return;
            }
            if (displayTabRoot.scaleLockMonitor !== "") {
                displayTabRoot.scaleLockUntilMs = Date.now() + 900;
                scaleLockClearTimer.restart();
            }
            if (Date.now() < displayTabRoot.layoutLockUntilMs) {
                displayTabRoot.layoutLockUntilMs = Date.now() + 500;
            }
            if (Date.now() < displayTabRoot.powerLockUntilMs) {
                displayTabRoot.powerLockUntilMs = Date.now() + 500;
            }
            reloadMonitorsDebounceTimer.interval = 350;
            reloadMonitorsDebounceTimer.restart();
        }
    }

    function enqueueMonitorApply(cmd) {
        if (monitorApplyProc.running) {
            let nextQueue = displayTabRoot.queuedApplyCmds.slice();
            nextQueue.push(cmd);
            displayTabRoot.queuedApplyCmds = nextQueue;
            return;
        }
        monitorApplyProc.command = cmd;
        monitorApplyProc.running = true;
    }


    function loadFallbackScreens() {
        if (typeof Quickshell !== "undefined" && Quickshell.screens && Quickshell.screens.length > 0) {
            let mList = [];
            let allZero = true;
            for (let k = 0; k < Quickshell.screens.length; k++) {
                let s0 = Quickshell.screens[k];
                if (s0 && ((s0.x || 0) !== 0 || (s0.y || 0) !== 0)) {
                    allZero = false;
                    break;
                }
            }
            let curX = 0;
            for (let i = 0; i < Quickshell.screens.length; i++) {
                let scr = Quickshell.screens[i];
                if (scr && scr.name) {
                    let w = scr.width || 1920;
                    let h = scr.height || 1080;
                    let sc = (scr.scale !== undefined && scr.scale > 0) ? scr.scale : 1.0;
                    let sx = (allZero && Quickshell.screens.length > 1) ? curX : (scr.x || 0);
                    let sy = scr.y || 0;
                    curX += Math.max(1, Math.round(w / sc));
                    mList.push({
                        name: scr.name,
                        dimensions: w + "x" + h,
                        framerate: "60",
                        scale: sc,
                        x: sx,
                        y: sy,
                        transform: "normal",
                        active: true
                    });
                }
            }
            if (mList.length > 0) {
                displayTabRoot.syncMonitorModels(mList);
                displayTabRoot.refreshDisplaySettings();
            }
        }
    }

    function reloadMonitors() {
        if (displayTabRoot.compositor === "niri" || displayTabRoot.compositor === "sway" || displayTabRoot.compositor === "mango" || displayTabRoot.compositor === "hyprland" || displayTabRoot.compositor === "driftwm" || displayTabRoot.compositor === "umbriel") {
            if (monitorDetector.running) return;
            monitorDetector.running = true;
        } else {
            loadFallbackScreens();
        }
    }

    function updateMonitorSetting(monName, key, value) {
        if (!monName) return;
        if (key === "enabled") {
            Gamma.setEnabled(monName, value);
            displayTabRoot.refreshDisplaySettings();
            return;
        }
        if (key === "auto") {
            Gamma.setAuto(monName, value);
            displayTabRoot.refreshDisplaySettings();
            return;
        }
        if (key === "temperature") {
            Gamma.setTemperature(monName, value);
            displayTabRoot.refreshDisplaySettings();
            return;
        }

        let current = Config.getSetting("display", defaultDisplaySettings);
        if (!current.monitors) current.monitors = {};
        if (!current.monitors[monName]) current.monitors[monName] = {};

        current.monitors[monName][key] = value;
        Config.setSetting("display", current);
        displayTabRoot.displaySettings = JSON.parse(JSON.stringify(current));
    }

    function _compositorArgs() {
        return (displayTabRoot.compositor && displayTabRoot.compositor !== "unknown")
            ? ["--compositor", displayTabRoot.compositor]
            : [];
    }

    function applyMonitorPower(monName, enabled) {
        if (!monName) return;
        let nextEnabled = Boolean(enabled);
        let mon = displayTabRoot.monitorsByName[monName] || displayTabRoot.monitorsList.find(m => m && m.name === monName);
        if (!nextEnabled && mon && mon.active !== false && displayTabRoot.activeMonitorCount <= 1) {
            return;
        }

        displayTabRoot.powerLockUntilMs = Date.now() + 2500;

        let updatedList = displayTabRoot.monitorsList.map(function(m) {
            if (!m || m.name !== monName) return m;
            let copy = Object.assign({}, m);
            copy.active = nextEnabled;
            return copy;
        });
        displayTabRoot.syncMonitorModels(updatedList);
        displayTabRoot.updateMonitorSetting(monName, "powerEnabled", nextEnabled);

        let resStr = mon ? (mon.dimensions || "1920x1080") : "1920x1080";
        let rateStr = mon ? (mon.framerate || "60") : "60";
        let scaleVal = displayTabRoot.normalizeScaleFactor(mon && mon.scale !== undefined ? mon.scale : 1.0);
        let px = (mon && mon.x !== undefined && mon.x !== null) ? Math.round(Number(mon.x)) : 0;
        let py = (mon && mon.y !== undefined && mon.y !== null) ? Math.round(Number(mon.y)) : 0;

        let cmd = [
            "python3",
            Caching.serpantinumDir + "/scripts/system/monitor_manager.py",
            "set-power",
            "--name", monName,
            "--enabled", nextEnabled ? "1" : "0",
            "--resolution", resStr,
            "--framerate", rateStr,
            "--scale", scaleVal.toString(),
            "--x", px.toString(),
            "--y", py.toString()
        ].concat(displayTabRoot._compositorArgs());
        displayTabRoot.enqueueMonitorApply(cmd);
    }

    function applyMonitorLayout(layoutItems) {
        if (!Array.isArray(layoutItems) || layoutItems.length === 0) return;
        displayTabRoot.layoutLockUntilMs = Date.now() + 2500;

        let posMap = {};
        for (let i = 0; i < layoutItems.length; i++) {
            let item = layoutItems[i];
            if (item && item.name) {
                posMap[item.name] = {
                    x: Math.round(Number(item.x || 0)),
                    y: Math.round(Number(item.y || 0))
                };
            }
        }

        let updatedList = displayTabRoot.monitorsList.map(function(m) {
            if (!m || !m.name || !posMap[m.name]) return m;
            let copy = Object.assign({}, m);
            copy.x = posMap[m.name].x;
            copy.y = posMap[m.name].y;
            return copy;
        });
        displayTabRoot.syncMonitorModels(updatedList);

        let current = Config.getSetting("display", defaultDisplaySettings);
        if (!current.monitors) current.monitors = {};
        let payload = [];
        for (let j = 0; j < updatedList.length; j++) {
            let m = updatedList[j];
            if (!m || !m.name) continue;
            if (!current.monitors[m.name]) current.monitors[m.name] = {};
            let px = (m.x !== undefined && m.x !== null) ? Math.round(Number(m.x)) : 0;
            let py = (m.y !== undefined && m.y !== null) ? Math.round(Number(m.y)) : 0;
            current.monitors[m.name].x = px;
            current.monitors[m.name].y = py;
            payload.push({
                name: m.name,
                x: px,
                y: py,
                resolution: m.dimensions || "1920x1080",
                framerate: m.framerate || "60",
                scale: m.scale !== undefined ? Number(m.scale) : 1.0
            });
        }
        Config.setSetting("display", current);
        displayTabRoot.displaySettings = JSON.parse(JSON.stringify(current));

        displayTabRoot.enqueueMonitorApply([
            "python3",
            Caching.serpantinumDir + "/scripts/system/monitor_manager.py",
            "set-layout",
            "--layout", JSON.stringify(payload)
        ].concat(displayTabRoot._compositorArgs()));
    }

    function _shiftFlushSiblingsForResize(changedMonName, oldBox, updatedList) {
        if (!oldBox || updatedList.length < 2) return;
        let changedItem = updatedList.find(m => m && m.name === changedMonName);
        if (!changedItem) return;
        let newBox = displayTabRoot.logicalBoxFor(changedItem);
        let dx = newBox.logW - oldBox.logW;
        let dy = newBox.logH - oldBox.logH;
        if (dx === 0 && dy === 0) return;

        let shifted = [];
        let changedAny = false;
        for (let i = 0; i < updatedList.length; i++) {
            let m = updatedList[i];
            if (!m || !m.name) continue;
            let b = displayTabRoot.logicalBoxFor(m);
            let nx = b.x;
            let ny = b.y;
            if (m.name !== changedMonName) {
                if (Math.abs(b.x - (oldBox.x + oldBox.logW)) <= 4) {
                    nx += dx;
                    changedAny = true;
                }
                if (Math.abs(b.y - (oldBox.y + oldBox.logH)) <= 4) {
                    ny += dy;
                    changedAny = true;
                }
            }
            shifted.push({ name: m.name, x: nx, y: ny });
        }
        if (changedAny) {
            displayTabRoot.applyMonitorLayout(shifted);
        }
    }

    function applyMonitorResolution(monName, resStr, rateStr) {
        if (!monName || !resStr) return;
        let mon = displayTabRoot.monitorsByName[monName] || displayTabRoot.monitorsList.find(m => m.name === monName);
        let oldBox = mon ? displayTabRoot.logicalBoxFor(mon) : null;
        let scaleVal = displayTabRoot.normalizeScaleFactor(mon ? (mon.scale !== undefined ? mon.scale : 1.0) : 1.0);
        let rStr = rateStr || (mon ? mon.framerate : "60") || "60";

        let updatedList = displayTabRoot.monitorsList.map(function(m) {
            if (!m || m.name !== monName) return m;
            let copy = Object.assign({}, m);
            copy.dimensions = resStr;
            copy.framerate = rStr;
            return copy;
        });
        displayTabRoot.syncMonitorModels(updatedList);

        let cmd = [
            "python3",
            Caching.serpantinumDir + "/scripts/system/monitor_manager.py",
            "set",
            "--name", monName,
            "--resolution", resStr,
            "--framerate", rStr,
            "--scale", scaleVal.toString()
        ].concat(displayTabRoot._compositorArgs());
        displayTabRoot.enqueueMonitorApply(cmd);

        displayTabRoot.updateMonitorSetting(monName, "resolution", resStr);
        if (rStr) displayTabRoot.updateMonitorSetting(monName, "framerate", rStr);
        displayTabRoot._shiftFlushSiblingsForResize(monName, oldBox, updatedList);
    }

    function applyMonitorFramerate(monName, rateStr) {
        if (!monName || !rateStr) return;
        let mon = displayTabRoot.monitorsByName[monName] || displayTabRoot.monitorsList.find(m => m.name === monName);
        let resStr = mon ? (mon.dimensions || "1920x1080") : "1920x1080";
        applyMonitorResolution(monName, resStr, rateStr);
    }

    function applyMonitorScale(monName, scaleVal) {
        if (!monName || scaleVal === undefined) return;
        let cleanScale = Math.max(0.5, Math.min(3.0, Math.round(Number(scaleVal) * 10000) / 10000));
        if (isNaN(cleanScale)) cleanScale = 1.0;

        let mon = displayTabRoot.monitorsByName[monName] || displayTabRoot.monitorsList.find(m => m.name === monName);
        let oldBox = mon ? displayTabRoot.logicalBoxFor(mon) : null;
        if (displayTabRoot.compositor === "hyprland" && mon && mon.dimensions && mon.dimensions.indexOf("x") !== -1) {
            let dims = mon.dimensions.split("x");
            let w = parseInt(dims[0], 10);
            let h = parseInt(dims[1], 10);
            if (!isNaN(w) && !isNaN(h) && w > 0 && h > 0) {
                let valid = displayTabRoot.validScalesForResolution(w, h);
                cleanScale = displayTabRoot.nearestValidScaleFromList(valid, cleanScale);
            }
        }

        displayTabRoot.scaleLockMonitor = monName;
        displayTabRoot.scaleLockUntilMs = Date.now() + 2500;
        scaleLockClearTimer.stop();

        let updatedList = displayTabRoot.monitorsList.map(function(m) {
            if (!m || m.name !== monName) return m;
            let copy = Object.assign({}, m);
            copy.scale = cleanScale;
            return copy;
        });
        displayTabRoot.syncMonitorModels(updatedList);

        let cmd = [
            "python3",
            Caching.serpantinumDir + "/scripts/system/monitor_manager.py",
            "set",
            "--name", monName,
            "--scale", cleanScale.toString()
        ].concat(displayTabRoot._compositorArgs());
        displayTabRoot.enqueueMonitorApply(cmd);

        displayTabRoot.updateMonitorSetting(monName, "scale", cleanScale);
        displayTabRoot._shiftFlushSiblingsForResize(monName, oldBox, updatedList);
    }

    function updateMonitorSettingDebounced(monName, tempVal) {
        pendingMonName = monName;
        pendingMonTemp = tempVal;
        tempDebounceTimer.restart();
    }

    function flushMonitorSetting(monName) {
        tempDebounceTimer.stop();
        if (pendingMonName === monName) {
            let name = pendingMonName;
            let val = pendingMonTemp;
            pendingMonName = "";
            Gamma.setTemperature(name, val);
            displayTabRoot.refreshDisplaySettings();
        }
    }

    Timer {
        id: tempDebounceTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (displayTabRoot.pendingMonName !== "") {
                let name = displayTabRoot.pendingMonName;
                let val = displayTabRoot.pendingMonTemp;
                displayTabRoot.pendingMonName = "";
                Gamma.setTemperature(name, val);
                displayTabRoot.refreshDisplaySettings();
            }
        }
    }

    property alias scaleDebounceTimer: scaleDebounceTimer

    Timer {
        id: scaleDebounceTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (displayTabRoot.pendingMonScaleName !== "") {
                let targetName = displayTabRoot.pendingMonScaleName;
                let targetVal = displayTabRoot.pendingMonScaleVal;
                displayTabRoot.pendingMonScaleName = "";
                displayTabRoot.applyMonitorScale(targetName, targetVal);
            }
        }
    }

    Timer {
        id: reloadMonitorsDebounceTimer
        interval: 220
        repeat: false
        onTriggered: displayTabRoot.reloadMonitors()
    }

    Component.onCompleted: {
        displayTabRoot.refreshDisplaySettings();
        if (DisplayCache.monitors.length > 0) {
            Qt.callLater(function() { displayTabRoot.animateCards = true; });
        } else {
            displayTabRoot.loadFallbackScreens();
        }
        if (visible) {
            displayTabRoot.reloadMonitors();
        }
    }

    onVisibleChanged: {
        if (visible) {
            displayTabRoot.refreshDisplaySettings();
            displayTabRoot.reloadMonitors();
        } else {
            reloadMonitorsDebounceTimer.stop();
        }
    }

    Connections {
        target: rootObj
        function onVisibleChanged() {
            if (rootObj && rootObj.visible && displayTabRoot.visible) {
                displayTabRoot.refreshDisplaySettings();
                displayTabRoot.reloadMonitors();
            }
        }
    }

    function scheduleExternalMonitorReload() {
        displayTabRoot.refreshDisplaySettings();
        if (displayTabRoot.visible && !monitorApplyProc.running && displayTabRoot.queuedApplyCmds.length === 0 && displayTabRoot.pendingMonScaleName === "" && Date.now() >= displayTabRoot.scaleLockUntilMs && Date.now() >= displayTabRoot.layoutLockUntilMs && Date.now() >= displayTabRoot.powerLockUntilMs) {
            reloadMonitorsDebounceTimer.interval = 260;
            reloadMonitorsDebounceTimer.restart();
        }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            displayTabRoot.scheduleExternalMonitorReload();
        }
    }

    Repeater {
        model: Quickshell.screens
        delegate: Item {
            required property var modelData
            visible: false
            width: 0
            height: 0
            Connections {
                target: modelData
                ignoreUnknownSignals: true
                function onScaleChanged() {
                    displayTabRoot.scheduleExternalMonitorReload();
                }
                function onDevicePixelRatioChanged() {
                    displayTabRoot.scheduleExternalMonitorReload();
                }
            }
        }
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            displayTabRoot.scheduleExternalMonitorReload();
        }
    }

    Connections {
        target: typeof Location !== "undefined" ? Location : null
        function onLocationUpdated() {
            displayTabRoot.refreshDisplaySettings();
        }
    }

    Connections {
        target: typeof Gamma !== "undefined" ? Gamma : null
        ignoreUnknownSignals: true
        function onSettingsChanged() {
            displayTabRoot.refreshDisplaySettings();
        }
    }
}
