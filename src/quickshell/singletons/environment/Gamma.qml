pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    signal settingsChanged()

    property var defaultDisplaySettings: ({ "monitors": {} })
    property int defaultScheduleStart: 22
    property int defaultScheduleEnd: 5
    property int scheduleFadeDurationMs: 10000

    property var pendingTargets: ({})
    property var appliedStates: ({})
    property var activeFades: ({})
    property var expectedFadeToken: ({})
    property var currentJob: null
    property bool isBusy: false
    property bool initialSettingsApplied: false
    property int _stateRevision: 0
    property int _fadeGen: 0

    readonly property bool anyEnabled: {
        let _rev = _stateRevision;
        let _raw = (typeof Config !== "undefined") ? Config.rawSettings : null;
        return isAnyEnabled();
    }

    onSettingsChanged: _stateRevision++

    function normalizeHour(val, fallbackVal) {
        let num = Number(val);
        if (val === undefined || val === null || isNaN(num)) {
            return fallbackVal !== undefined ? fallbackVal : 0;
        }
        return ((Math.round(num) % 24) + 24) % 24;
    }

    function getSavedMonitorValue(monName, key, fallbackVal) {
        if (typeof Config === "undefined") return fallbackVal;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds) return fallbackVal;
        if (monName && ds.monitors && ds.monitors[monName] && ds.monitors[monName][key] !== undefined) {
            return ds.monitors[monName][key];
        }
        if (ds[key] !== undefined) {
            return ds[key];
        }
        if (ds.monitors) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                let m = ds.monitors[keys[i]];
                if (m && m[key] !== undefined) {
                    return m[key];
                }
            }
        }
        return fallbackVal;
    }

    function getSavedTemperature(monName) {
        return getSavedMonitorValue(monName, "temperature", 50);
    }

    function getSavedAuto(monName) {
        return getSavedMonitorValue(monName, "auto", false);
    }

    function getSavedScheduleStart(monName) {
        return normalizeHour(getSavedMonitorValue(monName, "scheduleStart", defaultScheduleStart), defaultScheduleStart);
    }

    function getSavedScheduleEnd(monName) {
        return normalizeHour(getSavedMonitorValue(monName, "scheduleEnd", defaultScheduleEnd), defaultScheduleEnd);
    }

    function kelvinFromTemp(temp) {
        let t = (temp !== undefined && temp !== null) ? Number(temp) : 50;
        if (t >= 1000) {
            return Math.min(Math.max(Math.round(t), 1000), 10000);
        }
        return Math.round(6500 - (t / 100) * (6500 - 2500));
    }

    function isInScheduleWindow(startHour, endHour, nowDate) {
        let s = normalizeHour(startHour, defaultScheduleStart);
        let e = normalizeHour(endHour, defaultScheduleEnd);
        if (s === e) return false;
        let d = nowDate || new Date();
        let h = d.getHours();
        return s < e ? (h >= s && h < e) : (h >= s || h < e);
    }

    function msUntilNextScheduleBoundary(startHour, endHour, nowDate) {
        let s = normalizeHour(startHour, defaultScheduleStart);
        let e = normalizeHour(endHour, defaultScheduleEnd);
        let d = nowDate || new Date();
        let nowMs = d.getTime();
        let hours = [s, e];
        let bestMs = 86400000;
        for (let dayOffset = 0; dayOffset <= 1; dayOffset++) {
            for (let i = 0; i < hours.length; i++) {
                let target = new Date(d.getFullYear(), d.getMonth(), d.getDate() + dayOffset, hours[i], 0, 0, 0);
                let diff = target.getTime() - nowMs;
                if (diff > 0 && diff < bestMs) {
                    bestMs = diff;
                }
            }
        }
        return bestMs;
    }

    function shellQuote(val) {
        return "'" + String(val).replace(/'/g, "'\\''") + "'";
    }

    function buildGammaSetCmd(monName, kelvin) {
        let kStr = String(Math.round(kelvin));
        if (monName) {
            return ["serpantinum-gamma", "set", "-o", String(monName), "--temperature", kStr];
        }
        return ["serpantinum-gamma", "set", "--temperature", kStr];
    }

    function resolveGammaScript() {
        let scriptPath = (typeof Caching !== "undefined" && Caching.serpantinumDir)
            ? Caching.serpantinumDir + "/scripts/gamma.sh"
            : "";
        if (!scriptPath) {
            let resolved = Qt.resolvedUrl("../../../scripts/gamma.sh").toString();
            if (resolved.indexOf("file://") === 0) {
                resolved = resolved.substring(7);
            }
            scriptPath = resolved;
        }
        return scriptPath;
    }

    function cancelFade(key) {
        delete expectedFadeToken[key];
        if (activeFades[key]) {
            delete activeFades[key];
        }
        if (Object.keys(activeFades).length === 0) {
            fadeTimer.stop();
        }
    }

    function startFade(key, monName, fromK, toK, durationMs, fadeToken) {
        let startClamp = Math.min(10000, Math.max(1000, Math.round(fromK)));
        let endClamp = Math.min(10000, Math.max(1000, Math.round(toK)));
        activeFades[key] = {
            "monName": monName || "",
            "fromMired": 1000000.0 / startClamp,
            "toMired": 1000000.0 / endClamp,
            "targetK": endClamp,
            "lastSentK": startClamp,
            "startMs": Date.now(),
            "durationMs": Math.max(1, durationMs),
            "fadeToken": fadeToken
        };
        if (!fadeTimer.running) {
            fadeTimer.restart();
        }
    }

    function scheduleNext() {
        if (isBusy || runnerProcess.running || fadeProcess.running || retryTimer.running) return;

        let keys = Object.keys(pendingTargets);
        if (keys.length === 0) return;

        let scriptPath = resolveGammaScript();
        if (!scriptPath) {
            retryTimer.interval = 100;
            retryTimer.restart();
            return;
        }

        let key = keys[0];
        let target = pendingTargets[key];
        delete pendingTargets[key];

        currentJob = target;
        isBusy = true;

        let cmd = ["bash", scriptPath];
        if (target.mode === "reset") {
            cmd.push("reset", target.monName);
        } else if (target.mode === "start_fade") {
            cmd.push("set", String(target.startK), target.monName, "manual");
        } else {
            cmd.push("set", String(target.targetK), target.monName, "manual");
        }

        runnerProcess.command = cmd;
        runnerProcess.running = true;
    }

    function onJobFinished(exitCode) {
        isBusy = false;
        if (!currentJob) {
            scheduleNext();
            return;
        }

        let finishedJob = currentJob;
        let key = finishedJob.monName || "global";

        if (exitCode !== 0) {
            if (finishedJob.retries > 0) {
                finishedJob.retries -= 1;
                currentJob = null;
                if (!pendingTargets[key]) {
                    pendingTargets[key] = finishedJob;
                }
                retryTimer.interval = 200;
                retryTimer.restart();
                return;
            } else {
                delete appliedStates[key];
                cancelFade(key);
            }
        } else if (finishedJob.mode === "start_fade") {
            let st = appliedStates[key];
            if (!pendingTargets[key] && expectedFadeToken[key] === finishedJob.fadeToken && st && st.activeEffect && st.autoMode) {
                startFade(key, finishedJob.monName, finishedJob.startK, finishedJob.targetK, scheduleFadeDurationMs, finishedJob.fadeToken);
            }
        }

        currentJob = null;
        scheduleNext();
    }

    Process {
        id: runnerProcess
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            root.onJobFinished(exitCode);
        }
    }

    Process {
        id: fadeProcess
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function() {
            root.scheduleNext();
        }
    }

    Timer {
        id: retryTimer
        interval: 200
        repeat: false
        onTriggered: root.scheduleNext()
    }

    Timer {
        id: fadeTimer
        interval: 50
        repeat: true
        onTriggered: {
            let keys = Object.keys(root.activeFades);
            if (keys.length === 0) {
                fadeTimer.stop();
                return;
            }
            if (root.isBusy || fadeProcess.running || Object.keys(root.pendingTargets).length > 0) {
                return;
            }
            let nowMs = Date.now();
            let cmds = [];
            let completed = [];
            for (let i = 0; i < keys.length; i++) {
                let key = keys[i];
                let f = root.activeFades[key];
                if (!f) continue;
                let t = f.durationMs > 0 ? Math.min(1.0, Math.max(0.0, (nowMs - f.startMs) / f.durationMs)) : 1.0;
                let eased = t < 0.5 ? 2.0 * t * t : 1.0 - Math.pow(-2.0 * t + 2.0, 2) / 2.0;
                let nextMired = f.fromMired + (f.toMired - f.fromMired) * eased;
                let nextK = t >= 1.0 ? f.targetK : Math.round(1000000.0 / Math.max(1.0, nextMired));
                if (nextK !== f.lastSentK || t >= 1.0) {
                    f.lastSentK = nextK;
                    cmds.push(root.buildGammaSetCmd(f.monName, nextK));
                }
                if (t >= 1.0) {
                    completed.push(key);
                }
            }
            for (let j = 0; j < completed.length; j++) {
                delete root.activeFades[completed[j]];
                delete root.expectedFadeToken[completed[j]];
            }
            if (Object.keys(root.activeFades).length === 0) {
                fadeTimer.stop();
            }
            if (cmds.length === 1) {
                fadeProcess.command = cmds[0];
                fadeProcess.running = true;
            } else if (cmds.length > 1) {
                let joined = cmds.map(function(parts) {
                    return parts.map(root.shellQuote).join(" ");
                }).join("; ");
                fadeProcess.command = ["bash", "-c", joined];
                fadeProcess.running = true;
            }
        }
    }

    Timer {
        id: scheduleCheckTimer
        interval: 10000
        repeat: false
        onTriggered: root.checkSchedules()
    }

    function isConnected(monName) {
        if (!monName || typeof Quickshell === "undefined" || !Quickshell.screens || Quickshell.screens.length === 0) return true;
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i] && Quickshell.screens[i].name === monName) return true;
        }
        return false;
    }

    function apply(monName, enabled, temp, autoMode, schedStart, schedEnd) {
        if (!isConnected(monName)) return;
        let key = monName || "global";
        let normEn = !!enabled;
        let normAu = !!autoMode;
        let normTemp = (temp !== undefined && temp !== null) ? Number(temp) : getSavedTemperature(monName);
        let normStart = (schedStart !== undefined && schedStart !== null) ? normalizeHour(schedStart, defaultScheduleStart) : getSavedScheduleStart(monName);
        let normEnd = (schedEnd !== undefined && schedEnd !== null) ? normalizeHour(schedEnd, defaultScheduleEnd) : getSavedScheduleEnd(monName);
        let shouldBeActive = normEn && (!normAu || isInScheduleWindow(normStart, normEnd, new Date()));
        let targetK = shouldBeActive ? kelvinFromTemp(normTemp) : 6500;

        let prev = appliedStates[key];
        if (prev && prev.enabled === normEn && prev.temp === normTemp && prev.autoMode === normAu
                && prev.schedStart === normStart && prev.schedEnd === normEnd
                && prev.activeEffect === shouldBeActive && prev.targetK === targetK) {
            return;
        }

        let wasActive = prev ? !!prev.activeEffect : false;
        let prevTargetK = prev ? prev.targetK : 6500;

        appliedStates[key] = {
            "enabled": normEn,
            "temp": normTemp,
            "autoMode": normAu,
            "schedStart": normStart,
            "schedEnd": normEnd,
            "activeEffect": shouldBeActive,
            "targetK": targetK
        };

        if (!shouldBeActive) {
            cancelFade(key);
            if (!prev || wasActive) {
                pendingTargets[key] = {
                    "mode": "reset",
                    "monName": monName || "",
                    "retries": 3
                };
                scheduleNext();
            }
            return;
        }

        let needsFade = normAu && !wasActive && targetK !== 6500;
        if (needsFade) {
            cancelFade(key);
            let token = (_fadeGen += 1);
            expectedFadeToken[key] = token;
            pendingTargets[key] = {
                "mode": "start_fade",
                "monName": monName || "",
                "startK": 6500,
                "targetK": targetK,
                "fadeToken": token,
                "retries": 3
            };
            scheduleNext();
            return;
        }

        if (wasActive && normAu && prevTargetK === targetK) {
            return;
        }

        cancelFade(key);
        pendingTargets[key] = {
            "mode": "set",
            "monName": monName || "",
            "targetK": targetK,
            "retries": 3
        };
        scheduleNext();
    }

    function _applyEntry(monName, entry, ds) {
        let isEn = (entry && entry.enabled !== undefined) ? entry.enabled : (ds && ds.enabled !== undefined ? ds.enabled : false);
        let isAu = (entry && entry.auto !== undefined) ? entry.auto : (ds && ds.auto !== undefined ? ds.auto : false);
        let temp = (entry && entry.temperature !== undefined) ? entry.temperature : getSavedTemperature(monName);
        let sStart = (entry && entry.scheduleStart !== undefined) ? entry.scheduleStart : getSavedScheduleStart(monName);
        let sEnd = (entry && entry.scheduleEnd !== undefined) ? entry.scheduleEnd : getSavedScheduleEnd(monName);
        apply(monName, isEn, temp, isAu, sStart, sEnd);
    }

    function _updateSetting(monName, updater) {
        if (typeof Config === "undefined") return;
        let current = Config.getSetting("display", defaultDisplaySettings);
        if (!current) current = { "monitors": {} };
        if (!monName) {
            updater(current);
            if (current.monitors) {
                let keys = Object.keys(current.monitors);
                for (let i = 0; i < keys.length; i++) {
                    if (!current.monitors[keys[i]]) current.monitors[keys[i]] = {};
                    updater(current.monitors[keys[i]]);
                }
            }
            Config.setSetting("display", current);
            let monKeys = current.monitors ? Object.keys(current.monitors) : [];
            if (monKeys.length > 0) {
                for (let j = 0; j < monKeys.length; j++) {
                    _applyEntry(monKeys[j], current.monitors[monKeys[j]], current);
                }
            } else {
                _applyEntry("", current, current);
            }
        } else {
            if (!current.monitors) current.monitors = {};
            if (!current.monitors[monName]) current.monitors[monName] = {};
            let changed = updater(current.monitors[monName]);
            if (changed === false) return;
            Config.setSetting("display", current);
            _applyEntry(monName, current.monitors[monName], current);
        }
        refreshScheduleTimer();
        root.settingsChanged();
    }

    function applyForMonitor(monName) {
        if (!monName) return;
        let ds = typeof Config !== "undefined" ? Config.getSetting("display", defaultDisplaySettings) : defaultDisplaySettings;
        let mSet = (ds && ds.monitors && ds.monitors[monName]) ? ds.monitors[monName] : {};
        _applyEntry(monName, mSet, ds);
        refreshScheduleTimer();
    }

    function setEnabled(monName, enabled) {
        if (typeof enabled === "undefined" && typeof monName === "boolean") {
            enabled = monName;
            monName = "";
        }
        let val = !!enabled;
        _updateSetting(monName, function(target) {
            if (monName && target.enabled === val) return false;
            target.enabled = val;
            return true;
        });
    }

    function setAuto(monName, autoMode) {
        if (typeof autoMode === "undefined" && typeof monName === "boolean") {
            autoMode = monName;
            monName = "";
        }
        let val = !!autoMode;
        _updateSetting(monName, function(target) {
            if (monName && target.auto === val) return false;
            target.auto = val;
            return true;
        });
    }

    function setTemperature(monName, temp) {
        if (typeof temp === "undefined" && (typeof monName === "number" || typeof monName === "string")) {
            temp = monName;
            monName = "";
        }
        let numTemp = Number(temp);
        _updateSetting(monName, function(target) {
            if (monName && target.temperature === numTemp) return false;
            target.temperature = numTemp;
            return true;
        });
    }

    function setSchedule(monName, startHour, endHour) {
        let s = normalizeHour(startHour, defaultScheduleStart);
        let e = normalizeHour(endHour, defaultScheduleEnd);
        _updateSetting(monName, function(target) {
            if (monName && target.scheduleStart === s && target.scheduleEnd === e) return false;
            target.scheduleStart = s;
            target.scheduleEnd = e;
            return true;
        });
    }

    function updateMonitorSetting(monName, key, value) {
        if (!monName || typeof Config === "undefined") return;
        _updateSetting(monName, function(target) {
            if (target[key] === value) return false;
            target[key] = value;
            return true;
        });
    }

    function reset(monName) {
        let key = monName || "global";
        cancelFade(key);
        let prev = appliedStates[key];
        if (prev && !prev.activeEffect && !prev.enabled) {
            return;
        }
        let temp = getSavedTemperature(monName);
        let sStart = getSavedScheduleStart(monName);
        let sEnd = getSavedScheduleEnd(monName);
        appliedStates[key] = {
            "enabled": false,
            "temp": temp,
            "autoMode": false,
            "schedStart": sStart,
            "schedEnd": sEnd,
            "activeEffect": false,
            "targetK": 6500
        };
        pendingTargets[key] = {
            "mode": "reset",
            "monName": monName || "",
            "retries": 3
        };
        scheduleNext();
        refreshScheduleTimer();
        root.settingsChanged();
    }

    function isAnyEnabled() {
        if (typeof Config === "undefined") return false;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (ds && ds.enabled) return true;
        if (!ds || !ds.monitors) return false;
        let keys = Object.keys(ds.monitors);
        for (let i = 0; i < keys.length; i++) {
            let m = ds.monitors[keys[i]];
            if (m && m.enabled) return true;
        }
        return false;
    }

    function toggleAll() {
        let target = !root.isAnyEnabled();
        let monNames = [];
        let ds = (typeof Config !== "undefined" && typeof Config.getSetting === "function") ? Config.getSetting("display", defaultDisplaySettings) : defaultDisplaySettings;
        let mons = (ds && ds.monitors) ? ds.monitors : {};
        for (let m in mons) {
            if (monNames.indexOf(m) === -1) {
                monNames.push(m);
            }
        }
        if (typeof Quickshell !== "undefined" && Quickshell.screens) {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                let scr = Quickshell.screens[i];
                if (scr && scr.name && monNames.indexOf(scr.name) === -1) {
                    monNames.push(scr.name);
                }
            }
        }
        if (monNames.length > 0) {
            for (let i = 0; i < monNames.length; i++) {
                setEnabled(monNames[i], target);
            }
        } else {
            setEnabled("", target);
        }
        return target;
    }

    function applyAll() {
        if (typeof Config === "undefined") return;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds) return;

        if (ds.monitors && Object.keys(ds.monitors).length > 0) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                let mName = keys[i];
                let mSet = ds.monitors[mName];
                if (mSet) {
                    let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
                    let prev = appliedStates[mName];
                    if (isEn || (prev && (prev.enabled || prev.activeEffect))) {
                        _applyEntry(mName, mSet, ds);
                    }
                }
            }
        } else if (ds.enabled !== undefined) {
            _applyEntry("", ds, ds);
        }
        refreshScheduleTimer();
        root.settingsChanged();
    }

    function checkSchedules() {
        if (typeof Config === "undefined") return;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds) {
            scheduleCheckTimer.stop();
            return;
        }
        if (ds.monitors && Object.keys(ds.monitors).length > 0) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                let mName = keys[i];
                let mSet = ds.monitors[mName];
                if (mSet && mSet.enabled && mSet.auto) {
                    _applyEntry(mName, mSet, ds);
                }
            }
        } else if (ds.enabled && ds.auto) {
            _applyEntry("", ds, ds);
        }
        refreshScheduleTimer();
    }

    function refreshScheduleTimer() {
        if (typeof Config === "undefined") {
            scheduleCheckTimer.stop();
            return;
        }
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds) {
            scheduleCheckTimer.stop();
            return;
        }
        let now = new Date();
        let minMs = 86400000;
        let hasActiveSchedule = false;
        if (ds.monitors && Object.keys(ds.monitors).length > 0) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                let mName = keys[i];
                let mSet = ds.monitors[mName];
                if (mSet && mSet.enabled && mSet.auto && isConnected(mName)) {
                    hasActiveSchedule = true;
                    let sStart = mSet.scheduleStart !== undefined ? mSet.scheduleStart : getSavedScheduleStart(mName);
                    let sEnd = mSet.scheduleEnd !== undefined ? mSet.scheduleEnd : getSavedScheduleEnd(mName);
                    let diff = msUntilNextScheduleBoundary(sStart, sEnd, now);
                    if (diff < minMs) minMs = diff;
                }
            }
        } else if (ds.enabled && ds.auto) {
            hasActiveSchedule = true;
            let sStart = ds.scheduleStart !== undefined ? ds.scheduleStart : defaultScheduleStart;
            let sEnd = ds.scheduleEnd !== undefined ? ds.scheduleEnd : defaultScheduleEnd;
            minMs = msUntilNextScheduleBoundary(sStart, sEnd, now);
        }

        if (!hasActiveSchedule) {
            scheduleCheckTimer.stop();
            return;
        }
        scheduleCheckTimer.interval = Math.max(250, Math.min(10000, minMs));
        scheduleCheckTimer.restart();
    }

    function ensureInitialApply() {
        if (typeof Config === "undefined") return;
        let ds = Config.getSetting("display", null);
        if (!ds) return;
        if ((!ds.monitors || Object.keys(ds.monitors).length === 0) && ds.enabled === undefined) return;
        root.initialSettingsApplied = true;
        root.applyAll();
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        ignoreUnknownSignals: true
        function onSettingsLoaded() {
            root.ensureInitialApply();
        }
    }

    Connections {
        target: typeof Quickshell !== "undefined" ? Quickshell : null
        ignoreUnknownSignals: true
        function onScreensChanged() {
            let keys = Object.keys(root.activeFades);
            for (let i = 0; i < keys.length; i++) {
                root.cancelFade(keys[i]);
            }
            root.appliedStates = ({});
            root.applyAll();
        }
    }

    Component.onCompleted: {
        root.ensureInitialApply();
    }
}
