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
    property string activeProfile: "balanced"
    property int thresholdEnd: 100
    property bool hasThresholdSupport: false
    property bool conservationMode: false
    property real healthPct: 100.0

    readonly property string batteryScriptPath: (typeof Caching !== "undefined" && Caching.serpantinumDir)
        ? (Caching.serpantinumDir + "/scripts/system/battery")
        : "battery"

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
                    
                    let prof = String(d.profile || "").toLowerCase();
                    if (prof === "low-power") prof = "power-saver";
                    powerTabRoot.activeProfile = prof || "balanced";

                    powerTabRoot.thresholdEnd = Number(d.threshold_end) || 100;
                    powerTabRoot.hasThresholdSupport = Boolean(d.has_threshold_support);
                    powerTabRoot.conservationMode = Boolean(d.is_conservation_mode || powerTabRoot.thresholdEnd <= 80);
                    powerTabRoot.healthPct = Number(d.health_pct) || 100.0;
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

            // 1. Status Section
            SettingsBlob {
                SettingsRow {
                    settingId: "power_status"
                    searchKeywords: "battery charge power status percentage watts level health"
                    rootObj: powerTabRoot.rootObj
                    icon: {
                        if (!powerTabRoot.hasBattery) return "󰚥";
                        if (powerTabRoot.status === "Charging") return "󰂄";
                        if (powerTabRoot.status === "Full") return "󰁹";
                        if (powerTabRoot.capacity > 80) return "󰁹";
                        if (powerTabRoot.capacity > 60) return "󰂁";
                        if (powerTabRoot.capacity > 40) return "󰁿";
                        if (powerTabRoot.capacity > 20) return "󰁽";
                        return "󰁺";
                    }
                    title: {
                        if (!powerTabRoot.hasBattery) return I18n.t("guide.power.status.ac", "AC Power Connected");
                        let st = powerTabRoot.status;
                        let statusLabel = st;
                        if (st === "Charging") statusLabel = I18n.t("guide.power.status.charging", "Charging");
                        else if (st === "Discharging") statusLabel = I18n.t("guide.power.status.discharging", "Discharging");
                        else if (st === "Full") statusLabel = I18n.t("guide.power.status.full", "Fully charged");
                        return powerTabRoot.capacity + "% • " + statusLabel;
                    }
                    description: {
                        if (!powerTabRoot.hasBattery) return I18n.t("guide.power.desc.ac_connected", "Running on AC adapter power");
                        let parts = [];
                        if (powerTabRoot.timeRemainingStr !== "") parts.push(powerTabRoot.timeRemainingStr);
                        if (powerTabRoot.powerWatts > 0) parts.push(powerTabRoot.powerWatts.toFixed(1) + " W");
                        if (powerTabRoot.healthPct > 0) parts.push(I18n.t("guide.power.health_label", "Health: %1%").arg(Math.round(powerTabRoot.healthPct)));
                        return parts.length > 0 ? parts.join(" • ") : I18n.t("guide.power.desc.battery_active", "Battery power supply");
                    }

                    ClickButton {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitHeight: rootObj.s(32)
                        buttonText: I18n.t("guide.power.refresh", "Refresh")
                        buttonIcon: "󰑐"
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.crust
                        cornerRadius: ThemeBackend.borderRadius
                        horizontalPadding: rootObj.s(14)
                        iconFontSize: rootObj.s(14)
                        textFontSize: rootObj.s(11)
                        onTriggered: powerTabRoot.refresh()
                    }
                }
            }

            // 2. Power Profiles Section
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

            // 3. Battery Care Section
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

                SettingsRow {
                    visible: powerTabRoot.hasThresholdSupport
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
    }
}
