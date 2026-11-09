import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"
import "../reusables/inputs"

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

    property bool cpuFreqSupported: false
    property var cpuFreqOptions: []
    property var cpuFreqLabels: []
    property int cpuFreqCurrentIndex: 0
    property int cpuFreqCurrentKhz: 0
    property string cpuFreqMode: "auto"

    property bool autoBrightnessEnabled: true
    property int powerSaverBrightness: 80

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

    function setCpuFreqMode(mode) {
        powerTabRoot.cpuFreqMode = mode;
        cmdProc.command = [powerTabRoot.batteryScriptPath, "set-freq-mode", mode];
        cmdProc.running = true;
    }

    function setCpuFreqLimit(khz) {
        powerTabRoot.cpuFreqCurrentKhz = khz;
        cmdProc.command = [powerTabRoot.batteryScriptPath, "set-freq", String(khz)];
        cmdProc.running = true;
    }

    function setAutoBrightness(enabled) {
        powerTabRoot.autoBrightnessEnabled = enabled;
        cmdProc.command = [powerTabRoot.batteryScriptPath, "set-auto-brightness", enabled ? "true" : "false"];
        cmdProc.running = true;
    }

    function setSaverBrightness(val) {
        powerTabRoot.powerSaverBrightness = val;
        cmdProc.command = [powerTabRoot.batteryScriptPath, "set-saver-brightness", String(val)];
        cmdProc.running = true;
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

                    if (d.cpu_freq) {
                        powerTabRoot.cpuFreqSupported = Boolean(d.cpu_freq.supported);
                        powerTabRoot.cpuFreqOptions = d.cpu_freq.options || [];
                        let labels = [];
                        for (let i = 0; i < powerTabRoot.cpuFreqOptions.length; i++) {
                            labels.push(powerTabRoot.cpuFreqOptions[i].label);
                        }
                        powerTabRoot.cpuFreqLabels = labels;
                        powerTabRoot.cpuFreqCurrentIndex = Number(d.cpu_freq.current_index) || 0;
                        powerTabRoot.cpuFreqCurrentKhz = Number(d.cpu_freq.current_khz) || 0;
                        powerTabRoot.cpuFreqMode = String(d.cpu_freq.mode || "auto");
                    }

                    if (d.auto_brightness !== undefined) {
                        powerTabRoot.autoBrightnessEnabled = Boolean(d.auto_brightness);
                    }
                    if (d.power_saver_brightness !== undefined) {
                        powerTabRoot.powerSaverBrightness = Number(d.power_saver_brightness) || 80;
                    }
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
            if (cpuFreqDropdown && cpuFreqDropdown.isOpen) cpuFreqDropdown.closePopup();
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

            // 2. Power Saver Settings Section (smoothly expands ONLY when Power Saver profile is active)
            CollapsibleSection {
                id: saverSection
                open: powerTabRoot.activeProfile === "power-saver" || powerTabRoot.activeProfile === "low-power"
                row: saverBlob

                SettingsBlob {
                    id: saverBlob
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right

                    // CPU Frequency Cap (SettingsGroup with Switch and Dropdown subSetting)
                    SettingsGroup {
                        id: cpuFreqGroup
                        visible: powerTabRoot.cpuFreqSupported && powerTabRoot.cpuFreqLabels.length > 0
                        settingId: "power_cpu_freq"
                        searchKeywords: "cpu frequency limit clock speed underclock downclock eco max freq"
                        rootObj: powerTabRoot.rootObj
                        icon: "󰻠"
                        title: I18n.t("guide.power.cpu_freq.title", "Лимит частоты процессора")
                        description: I18n.t("guide.power.cpu_freq.desc", "Ограничение максимальной частоты ядер для режима энергосбережения")
                        expanded: powerTabRoot.cpuFreqMode === "manual"

                        Switch {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: rootObj.s(170)
                            implicitHeight: rootObj.s(32)
                            options: [I18n.t("guide.power.cpu_mode_auto", "Auto"), I18n.t("guide.power.cpu_mode_manual", "Manual")]
                            currentIndex: powerTabRoot.cpuFreqMode === "manual" ? 1 : 0
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface0
                            textColor: ThemeBackend.subtext0
                            activeTextColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius
                            fontPixelSize: rootObj.s(11)
                            onToggled: function(index) {
                                let newMode = (index === 1) ? "manual" : "auto";
                                powerTabRoot.setCpuFreqMode(newMode);
                            }
                        }

                        subSettings: [
                            SettingsRow {
                                id: cpuFreqSubRow
                                rootObj: powerTabRoot.rootObj
                                baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                                icon: "󰍜"
                                title: I18n.t("guide.power.cpu_freq_value.title", "Максимальная частота")
                                description: I18n.t("guide.power.cpu_freq_value.desc", "Выбранный предел частоты для энергосбережения")

                                Dropdown {
                                    id: cpuFreqDropdown
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    implicitWidth: rootObj.s(130)
                                    implicitHeight: rootObj.s(32)
                                    options: powerTabRoot.cpuFreqLabels
                                    currentIndex: powerTabRoot.cpuFreqCurrentIndex
                                    accentColor: ThemeBackend.mauve
                                    baseColor: ThemeBackend.surface0
                                    hoverColor: ThemeBackend.surface1
                                    dropdownColor: ThemeBackend.surface0
                                    borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                    textColor: ThemeBackend.text
                                    activeTextColor: ThemeBackend.crust
                                    fontPixelSize: rootObj.s(11)
                                    onValueChanged: function(index, value) {
                                        if (powerTabRoot.cpuFreqOptions && powerTabRoot.cpuFreqOptions[index]) {
                                            let khz = powerTabRoot.cpuFreqOptions[index].khz;
                                            powerTabRoot.setCpuFreqLimit(khz);
                                        }
                                    }
                                }
                            }
                        ]
                    }

                    // Auto-reduce brightness toggle
                    SettingsRow {
                        settingId: "power_auto_brightness"
                        searchKeywords: "auto brightness reduce drop dim battery saver"
                        rootObj: powerTabRoot.rootObj
                        icon: "󰃟"
                        title: I18n.t("guide.power.auto_brightness.title", "Автопонижение яркости")
                        description: I18n.t("guide.power.auto_brightness.desc", "Снижать яркость экрана при переходе в режим энергосбережения")

                        Toggle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            checked: powerTabRoot.autoBrightnessEnabled
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface1
                            handleColor: ThemeBackend.crust
                            handleOffColor: ThemeBackend.text
                            onToggled: function(val) {
                                powerTabRoot.setAutoBrightness(val);
                            }
                        }
                    }

                    // Target brightness level (expands when Auto-brightness toggle is enabled)
                    CollapsibleSection {
                        open: powerTabRoot.autoBrightnessEnabled
                        row: targetBriRow

                        SettingsRow {
                            id: targetBriRow
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            baseColor: Qt.alpha(ThemeBackend.surface1, 0.25)
                            settingId: "power_saver_brightness_target"
                            searchKeywords: "target brightness percentage level saver"
                            rootObj: powerTabRoot.rootObj
                            icon: "󰃠"
                            title: I18n.t("guide.power.saver_brightness.title", "Целевой уровень яркости")
                            description: I18n.t("guide.power.saver_brightness.desc", "Уровень яркости экрана в режиме энергосбережения")

                            NumberSelector {
                                id: saverBriSelector
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                implicitWidth: rootObj.s(150)
                                implicitHeight: rootObj.s(32)
                                from: 50
                                to: 95
                                stepSize: 5
                                decimals: 0
                                suffix: "%"
                                value: Math.max(50, Math.min(95, powerTabRoot.powerSaverBrightness))
                                baseColor: ThemeBackend.surface0
                                accentColor: ThemeBackend.mauve
                                buttonColor: ThemeBackend.surface1
                                buttonTextColor: ThemeBackend.text
                                textColor: ThemeBackend.text
                                subTextColor: ThemeBackend.subtext0
                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                cornerRadius: ThemeBackend.borderRadius
                                fontFamily: ThemeBackend.fontFamily
                                fontPixelSize: rootObj.s(11)
                                onValueChanged: function(val) {
                                    let num = (typeof val === "number" && !isNaN(val)) ? val : value;
                                    let rounded = Math.round(num / 5) * 5;
                                    if (!isNaN(rounded) && rounded >= 50 && rounded <= 95 && powerTabRoot.powerSaverBrightness !== rounded) {
                                        powerTabRoot.setSaverBrightness(rounded);
                                    }
                                }
                                onTriggered: {
                                    let rounded = Math.round(saverBriSelector.value / 5) * 5;
                                    powerTabRoot.setSaverBrightness(rounded);
                                }
                            }
                        }
                    }

                    // Power saving optimizations repeater
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

            // 3. Battery Conservation Mode
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

            // 4. Charge limit (NumberSelector) - smoothly expands ONLY when Conservation mode is enabled
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

                        NumberSelector {
                            id: limitSelector
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: rootObj.s(150)
                            implicitHeight: rootObj.s(32)
                            from: 70
                            to: 95
                            stepSize: 5
                            decimals: 0
                            suffix: "%"
                            value: Math.max(70, Math.min(95, powerTabRoot.thresholdEnd))
                            baseColor: ThemeBackend.surface0
                            accentColor: ThemeBackend.mauve
                            buttonColor: ThemeBackend.surface1
                            buttonTextColor: ThemeBackend.text
                            textColor: ThemeBackend.text
                            subTextColor: ThemeBackend.subtext0
                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                            cornerRadius: ThemeBackend.borderRadius
                            fontFamily: ThemeBackend.fontFamily
                            fontPixelSize: rootObj.s(11)
                            onValueChanged: function(val) {
                                let num = (typeof val === "number" && !isNaN(val)) ? val : value;
                                let rounded = Math.round(num / 5) * 5;
                                if (!isNaN(rounded) && rounded >= 70 && rounded <= 95 && powerTabRoot.thresholdEnd !== rounded) {
                                    powerTabRoot.setLimit(rounded);
                                }
                            }
                            onTriggered: {
                                let rounded = Math.round(limitSelector.value / 5) * 5;
                                powerTabRoot.setLimit(rounded);
                            }
                        }
                    }
                }
            }
        }
    }
}
