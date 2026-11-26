import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

Rectangle {
    id: monDelegate
    required property var tab
    required property string modelData
    required property int index
    readonly property var rootObj: tab.rootObj

    Layout.fillWidth: true
    clip: true
    radius: ThemeBackend.borderRadius

    readonly property string monName: modelData
    readonly property var monitorInfo: (monDelegate.tab && monDelegate.tab.monitorsByName && monDelegate.tab.monitorsByName[monName])
        ? monDelegate.tab.monitorsByName[monName]
        : ({ name: monName, dimensions: "1920x1080", framerate: "60", scale: 1.0, active: true, modes: ["1920x1080"] })
    property var monSettings: (monDelegate.tab && monDelegate.tab.displaySettings && monDelegate.tab.displaySettings.monitors && monDelegate.tab.displaySettings.monitors[monName]) ? monDelegate.tab.displaySettings.monitors[monName] : ({})

    function resolveEffectiveScale() {
        if (monDelegate.monitorInfo && monDelegate.monitorInfo.scale !== undefined && Number(monDelegate.monitorInfo.scale) > 0) {
            return monDelegate.tab.normalizeScaleFactor(monDelegate.monitorInfo.scale);
        }
        if (monDelegate.monSettings && monDelegate.monSettings.scale !== undefined && Number(monDelegate.monSettings.scale) > 0) {
            return monDelegate.tab.normalizeScaleFactor(monDelegate.monSettings.scale);
        }
        return 1.0;
    }

    property bool monitorPowered: monSettings && monSettings.powerEnabled !== undefined ? monSettings.powerEnabled : (monitorInfo && monitorInfo.active !== undefined ? monitorInfo.active : true)
    property bool filterEnabled: monSettings && monSettings.enabled !== undefined ? monSettings.enabled : false
    property bool filterAuto: monSettings && monSettings.auto !== undefined ? monSettings.auto : false
    property real currentTemp: monSettings && monSettings.temperature !== undefined ? monSettings.temperature : 50
    property real currentScale: resolveEffectiveScale()
    property string currentFramerate: (monSettings && monSettings.framerate) ? String(monSettings.framerate) : (monitorInfo && monitorInfo.framerate ? String(monitorInfo.framerate) : "60")

    readonly property var validHyprlandScales: {
        if (!monDelegate.tab || monDelegate.tab.compositor !== "hyprland") return [];
        let dimsStr = (monDelegate.monitorInfo && monDelegate.monitorInfo.dimensions) ? monDelegate.monitorInfo.dimensions : "1920x1080";
        let parts = dimsStr.split("x");
        let w = parseInt(parts[0], 10);
        let h = parseInt(parts[1], 10);
        if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) return [1.0];
        return monDelegate.tab.validScalesForResolution(w, h);
    }

    function syncScaleSelector() {
        let targetPct = Math.max(50, Math.min(300, Math.round(monDelegate.currentScale * 100)));
        if (!scaleSelector.isEditing && Math.round(scaleSelector.value) !== targetPct) {
            scaleSelector.value = targetPct;
        }
    }

    function resolveHyprlandScaleForPct(targetPct, prevScale) {
        let list = monDelegate.validHyprlandScales;
        if (!list || list.length === 0) return Math.round(targetPct) / 100.0;
        let oldPct = Math.round(prevScale * 100);
        let diff = Math.round(targetPct) - oldPct;
        if (diff === 5) {
            for (let i = 0; i < list.length; i++) {
                if (Math.round(list[i] * 100) > oldPct) return list[i];
            }
            return list[list.length - 1];
        }
        if (diff === -5) {
            for (let i = list.length - 1; i >= 0; i--) {
                if (Math.round(list[i] * 100) < oldPct) return list[i];
            }
            return list[0];
        }
        return monDelegate.tab.nearestValidScaleFromList(list, targetPct / 100.0);
    }

    function scheduleScalePercent(pct) {
        let clampedPct = Math.max(50, Math.min(300, Math.round(pct)));
        let scaleVal = Math.round(clampedPct) / 100.0;
        if (monDelegate.tab && monDelegate.tab.compositor === "hyprland") {
            scaleVal = monDelegate.resolveHyprlandScaleForPct(clampedPct, monDelegate.currentScale);
        }
        if (Math.abs(monDelegate.currentScale - scaleVal) > 0.001) {
            monDelegate.currentScale = scaleVal;
        }
        monDelegate.syncScaleSelector();
        monDelegate.tab.pendingMonScaleName = monDelegate.monName;
        monDelegate.tab.pendingMonScaleVal = scaleVal;
        monDelegate.tab.scaleDebounceTimer.restart();
    }

    Connections {
        target: monDelegate.tab
        function onScaleSettled(settledMon) {
            if (settledMon === monDelegate.monName && !scaleSelector.isEditing && scaleSelector.holdDirection === 0) {
                let nextScale = monDelegate.resolveEffectiveScale();
                if (Math.abs(monDelegate.currentScale - nextScale) > 0.005) {
                    monDelegate.currentScale = nextScale;
                }
                monDelegate.syncScaleSelector();
            }
        }
    }

    readonly property var availableFramerates: {
        let res = monitorInfo.dimensions || "1920x1080";
        if (monitorInfo.resolutions_map && monitorInfo.resolutions_map[res] && monitorInfo.resolutions_map[res].length > 0) {
            return monitorInfo.resolutions_map[res];
        }
        if (monitorInfo.framerates && monitorInfo.framerates.length > 0) {
            return monitorInfo.framerates;
        }
        return [currentFramerate || "60"];
    }

    readonly property var framerateLabels: {
        let labels = [];
        for (let i = 0; i < availableFramerates.length; i++) {
            labels.push(availableFramerates[i] + " Hz");
        }
        return labels;
    }

    readonly property color cardTint: monitorPowered ? Qt.alpha(ThemeBackend.surface0, 0.4) : Qt.darker(Qt.alpha(ThemeBackend.surface0, 0.4), 1.1)
    color: monDelegateGlass.active ? "transparent" : cardTint

    GlassFill {
        id: monDelegateGlass
        anchors.fill: parent
        radius: parent.radius
        tintColor: monDelegate.cardTint
        tintAmount: 0.25
    }

    property real targetHeight: boxLayout.implicitHeight + rootObj.s(24)
    property bool appeared: !tab.animateCards

    property real appearProgress: appeared ? 1 : 0
    implicitHeight: targetHeight * appearProgress
    opacity: appeared ? 1.0 : 0.0

    Behavior on appearProgress { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 250 } }

    Component.onCompleted: {
        appeared = true;
    }

    onMonSettingsChanged: {
        if (!monSettings) return;
        if (monSettings.powerEnabled !== undefined) {
            monitorPowered = monSettings.powerEnabled;
        }
        filterEnabled = monSettings.enabled !== undefined ? monSettings.enabled : false;
        filterAuto = monSettings.auto !== undefined ? monSettings.auto : false;
        if (monDelegate.tab.pendingMonName !== monName && !temperatureSlider.pressed) {
            currentTemp = monSettings.temperature !== undefined ? monSettings.temperature : 50;
        }
        if (!monDelegate.tab.isScaleLockedFor(monName) && !scaleSelector.isEditing && scaleSelector.holdDirection === 0) {
            let nextScale = resolveEffectiveScale();
            if (Math.abs(currentScale - nextScale) > 0.005) {
                currentScale = nextScale;
            }
        }
        if (monSettings.framerate !== undefined) {
            currentFramerate = String(monSettings.framerate);
        }
    }

    onMonitorInfoChanged: {
        if (!monitorInfo) return;
        if (monSettings.powerEnabled === undefined && monitorInfo.active !== undefined) {
            monitorPowered = monitorInfo.active;
        }
        if (!monDelegate.tab.isScaleLockedFor(monName) && !scaleSelector.isEditing && scaleSelector.holdDirection === 0) {
            let nextScale = resolveEffectiveScale();
            if (Math.abs(currentScale - nextScale) > 0.005) {
                currentScale = nextScale;
            }
        }
        if (monSettings.framerate === undefined && monitorInfo.framerate) {
            currentFramerate = String(monitorInfo.framerate);
        }
    }

    onCurrentScaleChanged: {
        monDelegate.syncScaleSelector();
    }

    ColumnLayout {
        id: boxLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: rootObj.s(12)
        spacing: rootObj.s(6)

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: rootObj.s(6)
            Layout.leftMargin: rootObj.s(4)
            Layout.rightMargin: rootObj.s(4)
            spacing: rootObj.s(8)

            Text {
                text: monDelegate.monName
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(16)
                font.bold: true
                color: ThemeBackend.text
            }

            Item { Layout.fillWidth: true }

            Text {
                text: (monDelegate.monitorInfo.dimensions || "1920x1080") + " • " + monDelegate.currentFramerate + "Hz • " + Math.round(monDelegate.currentScale * 100) + "%"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(12)
                color: ThemeBackend.subtext0
            }
        }

        SettingsRow {
            visible: monDelegate.tab.monitorsList.length > 1
            rootObj: monDelegate.rootObj
            settingId: "display_monitor_enable_" + monDelegate.monName
            section: monDelegate.monName
            searchKeywords: "display monitor screen output enable disable power on off " + monDelegate.monName
            baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
            icon: "󰐥"
            title: I18n.t("guide.display.enable.title", "Enable Monitor")
            description: I18n.t("guide.display.enable.desc", "Turn display output on or off")

            Toggle {
                id: powerToggle
                checked: monDelegate.monitorPowered
                accentColor: ThemeBackend.mauve
                baseColor: ThemeBackend.surface1
                handleColor: ThemeBackend.crust
                handleOffColor: ThemeBackend.text
                onToggled: function(c) {
                    monDelegate.monitorPowered = c;
                    monDelegate.tab.updateMonitorSetting(monDelegate.monName, "powerEnabled", c);
                    monDelegate.tab.applyMonitorPower(monDelegate.monName, c);
                }

                Binding {
                    target: powerToggle
                    property: "checked"
                    value: monDelegate.monitorPowered
                }
            }
        }

        SettingsGroup {
            rootObj: monDelegate.rootObj
            settingId: "display_gamma_" + monDelegate.monName
            section: monDelegate.monName
            searchKeywords: "display night light blue light filter gamma redshift warm eye care " + monDelegate.monName
            icon: "󰖔"
            title: I18n.t("guide.display.gamma.title")
            description: I18n.t("guide.display.gamma.desc")
            expanded: monDelegate.filterEnabled

            Toggle {
                id: filterToggle
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                checked: monDelegate.filterEnabled
                accentColor: ThemeBackend.mauve
                baseColor: ThemeBackend.surface1
                handleColor: ThemeBackend.crust
                handleOffColor: ThemeBackend.text
                onToggled: function(c) {
                    monDelegate.filterEnabled = c;
                    Gamma.setEnabled(monDelegate.monName, c);
                    monDelegate.tab.refreshDisplaySettings();
                }

                Binding {
                    target: filterToggle
                    property: "checked"
                    value: monDelegate.filterEnabled
                }
            }

            subSettings: [
                SettingsRow {
                    rootObj: monDelegate.rootObj
                    settingId: "display_gamma_schedule_" + monDelegate.monName
                    section: monDelegate.monName
                    searchKeywords: "display night light blue light gamma schedule sunset sunrise automatic " + monDelegate.monName
                    baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                    icon: "󰥔"
                    title: I18n.t("guide.display.schedule.title")
                    description: I18n.t("guide.display.schedule.desc") + " " + monDelegate.tab.scheduleDescription

                    Toggle {
                        id: autoToggle
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: monDelegate.filterAuto
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(c) {
                            monDelegate.filterAuto = c;
                            Gamma.setAuto(monDelegate.monName, c);
                            monDelegate.tab.refreshDisplaySettings();
                        }

                        Binding {
                            target: autoToggle
                            property: "checked"
                            value: monDelegate.filterAuto
                        }
                    }
                },

                Item {
                    id: tempSectionWrapper
                    Layout.fillWidth: true
                    property bool isOpen: !monDelegate.filterAuto
                    clip: true
                    visible: implicitHeight > 0
                    opacity: isOpen ? 1.0 : 0.0
                    property real openProgress: isOpen ? 1 : 0
                    implicitHeight: tempInnerBox.implicitHeight * openProgress

                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on openProgress { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    SettingsRow {
                        id: tempInnerBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        rootObj: monDelegate.rootObj
                        settingId: "display_gamma_temp_" + monDelegate.monName
                        section: monDelegate.monName
                        searchKeywords: "display color temperature kelvin warm night light blue light gamma " + monDelegate.monName
                        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                        icon: "󰔏"
                        title: I18n.t("guide.display.temperature.title")
                        description: I18n.t("guide.display.temperature.desc")

                        Draggable {
                            id: temperatureSlider
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            Layout.rightMargin: rootObj.s(8)
                            implicitWidth: rootObj.s(220)
                            implicitHeight: rootObj.s(18)
                            from: 0
                            to: 100
                            stepSize: 1
                            defaultValue: 50
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v).toString() }
                            value: monDelegate.currentTemp
                            backgroundColor: ThemeBackend.surface0
                            accentColor: ThemeBackend.mauve
                            handleColor: ThemeBackend.text
                            handleBorderColor: ThemeBackend.mantle
                            onMoved: function(val) {
                                let rounded = Math.round(val);
                                if (monDelegate.currentTemp !== rounded) {
                                    monDelegate.currentTemp = rounded;
                                    monDelegate.tab.updateMonitorSettingDebounced(monDelegate.monName, rounded);
                                }
                            }
                            onDragFinished: {
                                monDelegate.tab.flushMonitorSetting(monDelegate.monName);
                            }
                        }
                    }
                }
            ]
        }

        SettingsRow {
            rootObj: monDelegate.rootObj
            baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
            icon: "󰍹"
            title: I18n.t("guide.display.resolution.title", "Screen Resolution")
            description: I18n.t("guide.display.resolution.desc", "Set monitor resolution")

            Dropdown {
                id: resDropdown
                implicitWidth: rootObj.s(180)
                implicitHeight: rootObj.s(32)
                cornerRadius: rootObj.s(6)
                options: (monDelegate.monitorInfo.modes && monDelegate.monitorInfo.modes.length > 0) ? monDelegate.monitorInfo.modes : [monDelegate.monitorInfo.dimensions || "1920x1080"]
                currentIndex: {
                    let cur = monDelegate.monitorInfo.dimensions || "1920x1080";
                    let idx = options.indexOf(cur);
                    return idx >= 0 ? idx : 0;
                }
                accentColor: ThemeBackend.mauve
                baseColor: ThemeBackend.surface0
                textColor: ThemeBackend.text
                onSelected: function(idx, val) {
                    monDelegate.tab.applyMonitorResolution(monDelegate.monName, val, monDelegate.currentFramerate || "60");
                }
            }
        }

        SettingsRow {
            visible: monDelegate.availableFramerates.length > 0
            rootObj: monDelegate.rootObj
            baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
            icon: "󰓅"
            title: I18n.t("guide.display.framerate.title", "Refresh Rate")
            description: I18n.t("guide.display.framerate.desc", "Set monitor refresh rate")

            Dropdown {
                id: rateDropdown
                implicitWidth: rootObj.s(180)
                implicitHeight: rootObj.s(32)
                cornerRadius: rootObj.s(6)
                options: monDelegate.framerateLabels
                currentIndex: {
                    let cur = monDelegate.currentFramerate;
                    let idx = monDelegate.availableFramerates.indexOf(cur);
                    return idx >= 0 ? idx : 0;
                }
                accentColor: ThemeBackend.mauve
                baseColor: ThemeBackend.surface0
                textColor: ThemeBackend.text
                onSelected: function(idx, val) {
                    if (monDelegate.availableFramerates && monDelegate.availableFramerates[idx]) {
                        let selectedRate = monDelegate.availableFramerates[idx];
                        monDelegate.currentFramerate = selectedRate;
                        monDelegate.tab.applyMonitorFramerate(monDelegate.monName, selectedRate);
                    }
                }
            }
        }

        SettingsRow {
            id: displayScaleRow
            rootObj: monDelegate.rootObj
            settingId: "display_uiscale_" + monDelegate.monName
            section: monDelegate.monName
            searchKeywords: "display wm monitor scale scaling hidpi dpi fractional zoom compositor windows " + monDelegate.monName
            baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
            icon: "󰍍"
            title: I18n.t("guide.display.uiscale.title", "Display Scale (WM)")
            description: I18n.t("guide.display.uiscale.desc", "Compositor and window scale for this monitor (50%–300%)")

            NumberSelector {
                id: scaleSelector
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                implicitWidth: rootObj.s(180)
                implicitHeight: rootObj.s(32)
                cornerRadius: rootObj.s(6)
                from: 50
                to: 300
                stepSize: 5
                decimals: 0
                suffix: "%"
                baseColor: ThemeBackend.surface0
                accentColor: ThemeBackend.mauve
                buttonColor: ThemeBackend.surface1
                buttonTextColor: ThemeBackend.text
                textColor: ThemeBackend.text
                subTextColor: ThemeBackend.subtext0
                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                fontPixelSize: rootObj.s(11)
                Component.onCompleted: {
                    scaleSelector.value = Math.max(50, Math.min(300, Math.round(monDelegate.currentScale * 100)));
                }
                onTriggered: {
                    let pct = Math.round(scaleSelector.value);
                    monDelegate.scheduleScalePercent(pct);
                }
            }
        }
    }
}
