import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

GuideTab {
    id: powerTabRoot

    property bool hasBattery: false
    property int capacity: 0
    property string status: "Unknown"
    property real powerWatts: 0.0
    property string timeRemainingStr: ""
    property int timeSeconds: 0
    property string activeProfile: "balanced"
    property int thresholdEnd: 100
    property bool hasThresholdSupport: false
    property bool conservationMode: false
    property real healthPct: 100.0
    property var optimizationsModel: []

    readonly property string batteryScriptPath: (typeof Caching !== "undefined" && Caching.serpantinumDir)
        ? (Caching.serpantinumDir + "/scripts/system/battery")
        : "battery"

    function formatTimeSeconds(sec) {
        if (!sec || sec <= 0 || sec > 86400 * 2) return "";
        let h = Math.floor(sec / 3600);
        let m = Math.floor((sec % 3600) / 60);
        let hUnit = I18n.t("guide.power.hours_short", "h");
        let mUnit = I18n.t("guide.power.minutes_short", "m");
        if (h > 0) {
            return h + hUnit + " " + (m < 10 ? "0" + m : m) + mUnit;
        }
        return m + mUnit;
    }

    function getTimeRemainingText() {
        if (powerTabRoot.timeSeconds <= 0) return "";
        let formatted = formatTimeSeconds(powerTabRoot.timeSeconds);
        if (!formatted) return "";
        if (powerTabRoot.status === "Discharging") {
            return I18n.t("guide.power.time_remaining", "~%1 remaining").arg(formatted);
        } else if (powerTabRoot.status === "Charging") {
            return I18n.t("guide.power.time_until_full", "~%1 until full").arg(formatted);
        }
        return "";
    }

    function refresh() {
        if (!statusProc.running) {
            statusProc.running = true;
        }
    }

    function setProfile(prof) {
        powerTabRoot.activeProfile = prof;
        cmdProc.command = [powerTabRoot.batteryScriptPath, "profile", prof];
        cmdProc.running = true;
    }

    function setLimit(limitVal) {
        cmdProc.command = [powerTabRoot.batteryScriptPath, "limit", String(limitVal)];
        cmdProc.running = true;
    }

    function toggleConservation() {
        if (powerTabRoot.conservationMode) {
            setLimit(100);
        } else {
            setLimit(80);
        }
    }

    function setOptimization(optId, enabled) {
        let list = [];
        for (let i = 0; i < powerTabRoot.optimizationsModel.length; i++) {
            let item = Object.assign({}, powerTabRoot.optimizationsModel[i]);
            if (item.id === optId) item.enabled = enabled;
            list.push(item);
        }
        powerTabRoot.optimizationsModel = list;
        cmdProc.command = [powerTabRoot.batteryScriptPath, "set-opt", optId, enabled ? "true" : "false"];
        cmdProc.running = true;
    }

    Process {
        id: statusProc
        command: [powerTabRoot.batteryScriptPath, "json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text);
                    powerTabRoot.hasBattery = Boolean(d.has_battery);
                    powerTabRoot.capacity = Number(d.capacity) || 0;
                    powerTabRoot.status = String(d.status || "Unknown");
                    powerTabRoot.powerWatts = Number(d.power_w) || 0.0;
                    powerTabRoot.timeRemainingStr = String(d.time_str || "");
                    powerTabRoot.timeSeconds = Number(d.time_seconds) || 0;
                    
                    let prof = String(d.profile || "").toLowerCase();
                    if (prof === "low-power") prof = "power-saver";
                    powerTabRoot.activeProfile = prof || "balanced";

                    powerTabRoot.thresholdEnd = Number(d.threshold_end) || 100;
                    powerTabRoot.hasThresholdSupport = Boolean(d.has_threshold_support);
                    powerTabRoot.conservationMode = Boolean(d.is_conservation_mode || powerTabRoot.thresholdEnd <= 80);
                    powerTabRoot.healthPct = Number(d.health_pct) || 100.0;
                    powerTabRoot.optimizationsModel = d.optimizations || [];
                } catch(e) {}
            }
        }
    }

    Process {
        id: cmdProc
        running: false
        onExited: {
            powerTabRoot.refresh();
        }
    }

    Timer {
        id: pollTimer
        interval: 3000
        repeat: true
        running: powerTabRoot.visible
        onTriggered: powerTabRoot.refresh()
    }

    onVisibleChanged: {
        if (visible) {
            powerTabRoot.refresh();
        } else {
            if (profileDropdown && profileDropdown.isOpen) profileDropdown.closePopup();
            if (limitDropdown && limitDropdown.isOpen) limitDropdown.closePopup();
        }
    }

    Component.onCompleted: {
        powerTabRoot.refresh();
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(8)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(8)
        contentHeight: settingsCol.implicitHeight + rootObj.s(16)
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            active: parent.moving || parent.movingVertically
            width: rootObj.s(4)
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: rootObj.s(4)
                radius: rootObj.s(2)
                color: ThemeBackend.surface2
            }
        }

        ColumnLayout {
            id: settingsCol
            width: parent.width - (parent.contentHeight > parent.height ? rootObj.s(6) : 0)
            spacing: rootObj.s(6)

            // 1. Power Profiles Section
            SettingsBlob {
                SettingsRow {
                    id: profileRow
                    settingId: "power_profile"
                    searchKeywords: "power profile battery saver balanced performance governor mode"
                    rootObj: powerTabRoot.rootObj
                    icon: "󰓅"
                    title: I18n.t("guide.power.profile.title", "Power profile")
                    description: I18n.t("guide.power.profile.desc", "Adjust performance and energy consumption")

                    Dropdown {
                        id: profileDropdown
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitWidth: rootObj.s(180)
                        implicitHeight: rootObj.s(32)
                        options: [
                            I18n.t("guide.power.profiles.saver_title", "Power Saver"),
                            I18n.t("guide.power.profiles.balanced_title", "Balanced"),
                            I18n.t("guide.power.profiles.perf_title", "Performance")
                        ]
                        currentIndex: {
                            if (powerTabRoot.activeProfile === "power-saver" || powerTabRoot.activeProfile === "low-power") return 0;
                            if (powerTabRoot.activeProfile === "performance") return 2;
                            return 1;
                        }
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface0
                        hoverColor: ThemeBackend.surface1
                        dropdownColor: ThemeBackend.surface0
                        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                        textColor: ThemeBackend.text
                        activeTextColor: ThemeBackend.crust
                        fontPixelSize: rootObj.s(11)
                        onValueChanged: function(index, value) {
                            let prof = "balanced";
                            if (index === 0) prof = "power-saver";
                            else if (index === 2) prof = "performance";
                            powerTabRoot.setProfile(prof);
                        }
                    }
                }
            }

            // 2. Battery Conservation Mode
            SettingsBlob {
                visible: powerTabRoot.hasBattery

                SettingsRow {
                    settingId: "power_conservation"
                    searchKeywords: "battery conservation protection limit 80 health prolong"
                    rootObj: powerTabRoot.rootObj
                    icon: "󰂄"
                    title: I18n.t("guide.power.threshold.conservation_title", "Conservation mode")
                    description: I18n.t("guide.power.threshold.conservation_desc", "Limit charging to 80% to prolong battery lifespan")

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: powerTabRoot.conservationMode
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(val) {
                            powerTabRoot.toggleConservation();
                        }
                    }
                }
            }

            // Charge limit (Dropdown) - smoothly expands ONLY when Conservation mode is enabled
            CollapsibleSection {
                open: powerTabRoot.hasBattery && powerTabRoot.conservationMode && powerTabRoot.hasThresholdSupport
                row: limitBlob

                SettingsBlob {
                    id: limitBlob
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right

                    SettingsRow {
                        settingId: "power_threshold_limit"
                        searchKeywords: "charge limit threshold percentage stop charging"
                        rootObj: powerTabRoot.rootObj
                        icon: "󰚥"
                        title: I18n.t("guide.power.threshold.custom_label", "Charge limit")
                        description: I18n.t("guide.power.threshold.custom_desc", "Maximum battery charge percentage")

                        Dropdown {
                            id: limitDropdown
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: rootObj.s(140)
                            implicitHeight: rootObj.s(32)
                            options: ["70%", "75%", "80%", "85%", "90%", "100%"]
                            currentIndex: {
                                let val = powerTabRoot.thresholdEnd;
                                if (val <= 70) return 0;
                                if (val <= 75) return 1;
                                if (val <= 80) return 2;
                                if (val <= 85) return 3;
                                if (val <= 90) return 4;
                                return 5;
                            }
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface0
                            hoverColor: ThemeBackend.surface1
                            dropdownColor: ThemeBackend.surface0
                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                            textColor: ThemeBackend.text
                            activeTextColor: ThemeBackend.crust
                            fontPixelSize: rootObj.s(11)
                            onValueChanged: function(index, value) {
                                let limits = [70, 75, 80, 85, 90, 100];
                                powerTabRoot.setLimit(limits[index]);
                            }
                        }
                    }
                }
            }

            // 3. Power Saving Optimizations Section
            SettingsBlob {
                visible: powerTabRoot.optimizationsModel && powerTabRoot.optimizationsModel.length > 0

                Repeater {
                    model: powerTabRoot.optimizationsModel

                    delegate: SettingsRow {
                        id: optRow
                        required property var modelData
                        required property int index

                        settingId: "power_opt_" + modelData.id
                        searchKeywords: "power optimization " + modelData.id + " battery save tweak"
                        rootObj: powerTabRoot.rootObj
                        icon: modelData.icon || "󰚥"
                        title: I18n.t("guide.power.optimizations." + modelData.id + "_title", modelData.title)
                        description: I18n.t("guide.power.optimizations." + modelData.id + "_desc", modelData.desc)

                        Toggle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            checked: Boolean(modelData.enabled)
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface1
                            handleColor: ThemeBackend.crust
                            handleOffColor: ThemeBackend.text
                            onToggled: function(val) {
                                powerTabRoot.setOptimization(modelData.id, val);
                            }
                        }
                    }
                }
            }
        }
    }
}
