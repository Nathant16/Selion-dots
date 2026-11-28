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
    property bool animateCards: false

    readonly property string compositor: Compositor.name

    property string pendingMonName: ""
    property real pendingMonTemp: 50

    property string pendingMonScaleName: ""
    property real pendingMonScaleVal: 1.0
    property var queuedApplyCmd: null
    property string scaleLockMonitor: ""
    property double scaleLockUntilMs: 0

    function isScaleLockedFor(monName) {
        if (!monName) return false;
        if (displayTabRoot.pendingMonScaleName === monName) return true;
        if (displayTabRoot.scaleLockMonitor === monName) {
            if (monitorApplyProc.running || displayTabRoot.queuedApplyCmd !== null) return true;
            if (Date.now() < displayTabRoot.scaleLockUntilMs) return true;
        }
        return false;
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
            if (displayTabRoot.queuedApplyCmd !== null) {
                let nextCmd = displayTabRoot.queuedApplyCmd;
                displayTabRoot.queuedApplyCmd = null;
                monitorApplyProc.command = nextCmd;
                monitorApplyProc.running = true;
                return;
            }
            if (displayTabRoot.scaleLockMonitor !== "") {
                displayTabRoot.scaleLockUntilMs = Date.now() + 900;
                scaleLockClearTimer.restart();
            }
            reloadMonitorsDebounceTimer.interval = 280;
            reloadMonitorsDebounceTimer.restart();
        }
    }

    function enqueueMonitorApply(cmd) {
        if (monitorApplyProc.running) {
            displayTabRoot.queuedApplyCmd = cmd;
            return;
        }
        monitorApplyProc.command = cmd;
        monitorApplyProc.running = true;
    }


    function loadFallbackScreens() {
        if (typeof Quickshell !== "undefined" && Quickshell.screens && Quickshell.screens.length > 0) {
            let mList = [];
            for (let i = 0; i < Quickshell.screens.length; i++) {
                let scr = Quickshell.screens[i];
                if (scr && scr.name) {
                    let w = scr.width || 1920;
                    let h = scr.height || 1080;
                    let sc = (scr.scale !== undefined && scr.scale > 0) ? scr.scale : 1.0;
                    mList.push({
                        name: scr.name,
                        dimensions: w + "x" + h,
                        framerate: "60",
                        scale: sc,
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

    function applyMonitorPower(monName, enabled) {
        if (!monName) return;
        let mon = displayTabRoot.monitorsList.find(m => m.name === monName);
        let modeStr = mon ? (mon.dimensions + "@" + mon.framerate) : "preferred";
        let scaleVal = mon ? mon.scale : 1.0;
        let cmd = Compositor.outputEnableCommand(monName, enabled, modeStr, scaleVal);
        if (cmd !== "") {
            Quickshell.execDetached(["bash", "-c", cmd]);
        }
    }

    function applyMonitorResolution(monName, resStr, rateStr) {
        if (!monName || !resStr) return;
        let mon = displayTabRoot.monitorsByName[monName] || displayTabRoot.monitorsList.find(m => m.name === monName);
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
            "--scale", scaleVal.toString(),
            "--compositor", displayTabRoot.compositor
        ];
        displayTabRoot.enqueueMonitorApply(cmd);

        displayTabRoot.updateMonitorSetting(monName, "resolution", resStr);
        if (rStr) displayTabRoot.updateMonitorSetting(monName, "framerate", rStr);
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
            "--scale", cleanScale.toString(),
            "--compositor", displayTabRoot.compositor
        ];
        displayTabRoot.enqueueMonitorApply(cmd);

        displayTabRoot.updateMonitorSetting(monName, "scale", cleanScale);
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
        if (displayTabRoot.visible && !monitorApplyProc.running && displayTabRoot.queuedApplyCmd === null && displayTabRoot.pendingMonScaleName === "" && Date.now() >= displayTabRoot.scaleLockUntilMs) {
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
