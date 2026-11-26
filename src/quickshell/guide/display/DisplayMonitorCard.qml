import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

Rectangle {
    id: monDelegate
    required property var tab
    required property var modelData
    required property int index
    readonly property var rootObj: tab.rootObj

    Layout.fillWidth: true
    clip: true
    radius: ThemeBackend.borderRadius

    property string monName: modelData.name
    property var monSettings: (monDelegate.tab && monDelegate.tab.displaySettings && monDelegate.tab.displaySettings.monitors && monDelegate.tab.displaySettings.monitors[monName]) ? monDelegate.tab.displaySettings.monitors[monName] : ({})

    property bool monitorPowered: monSettings && monSettings.powerEnabled !== undefined ? monSettings.powerEnabled : (modelData && modelData.active !== undefined ? modelData.active : true)
    property bool filterEnabled: monSettings && monSettings.enabled !== undefined ? monSettings.enabled : false
    property bool filterAuto: monSettings && monSettings.auto !== undefined ? monSettings.auto : false
    property real currentTemp: monSettings && monSettings.temperature !== undefined ? monSettings.temperature : 50
    property real currentScale: (monSettings && monSettings.scale !== undefined) ? monSettings.scale : (modelData.scale !== undefined ? modelData.scale : 1.0)
    property string currentFramerate: (monSettings && monSettings.framerate) ? String(monSettings.framerate) : (modelData && modelData.framerate ? String(modelData.framerate) : "60")

    readonly property var availableFramerates: {
        let res = modelData.dimensions || "1920x1080";
        if (modelData.resolutions_map && modelData.resolutions_map[res] && modelData.resolutions_map[res].length > 0) {
            return modelData.resolutions_map[res];
        }
        if (modelData.framerates && modelData.framerates.length > 0) {
            return modelData.framerates;
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
        if (monSettings.scale !== undefined && monDelegate.tab.pendingMonScaleName !== monName && !uiScaleSlider.isDragging) {
            currentScale = monSettings.scale;
        }
        if (monSettings.framerate !== undefined) {
            currentFramerate = String(monSettings.framerate);
        }
    }

    onModelDataChanged: {
        if (monSettings.powerEnabled === undefined && modelData.active !== undefined) {
            monitorPowered = modelData.active;
        }
        if (monDelegate.tab.pendingMonScaleName !== monName && !uiScaleSlider.isDragging) {
            currentScale = (monSettings && monSettings.scale !== undefined) ? monSettings.scale : (modelData.scale !== undefined ? modelData.scale : 1.0);
        }
        if (monSettings.framerate === undefined && modelData.framerate) {
            currentFramerate = String(modelData.framerate);
        }
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
                text: modelData.name
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(16)
                font.bold: true
                color: ThemeBackend.text
            }

            Item { Layout.fillWidth: true }

            Text {
                text: modelData.dimensions + " • " + modelData.framerate + "Hz"
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
                options: (modelData.modes && modelData.modes.length > 0) ? modelData.modes : [modelData.dimensions || "1920x1080"]
                currentIndex: {
                    let cur = modelData.dimensions || "1920x1080";
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
            readonly property bool isMango: monDelegate.tab.compositor === "mango"
            rootObj: monDelegate.rootObj
            settingId: "display_uiscale_" + monDelegate.monName
            section: monDelegate.monName
            searchKeywords: "display wm monitor scale scaling hidpi dpi fractional zoom compositor windows " + monDelegate.monName
            baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
            icon: "󰍍"
            title: I18n.t("guide.display.uiscale.title", "Display Scale (WM)")
            description: displayScaleRow.isMango
                ? I18n.t("guide.display.uiscale.desc_mango", "Integer WM scale only (Mango does not support fractional scaling — use Quickshell UI Scale in General)")
                : I18n.t("guide.display.uiscale.desc", "Compositor and window scale for this monitor (e.g. 100%, 125%, 150%, 200%)")

            Draggable {
                id: uiScaleSlider
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.rightMargin: rootObj.s(8)
                implicitWidth: rootObj.s(220)
                implicitHeight: rootObj.s(18)
                from: displayScaleRow.isMango ? 100 : 50
                to: displayScaleRow.isMango ? 300 : 250
                stepSize: displayScaleRow.isMango ? 100 : 5
                defaultValue: 100
                alwaysShowHandle: displayScaleRow.isMango
                showValueBubble: true
                valueFormatter: function(v) { return Math.round(v) + "%" }
                value: displayScaleRow.isMango
                    ? Math.max(100, Math.min(300, Math.round(modelData && modelData.scale !== undefined ? modelData.scale : monDelegate.currentScale) * 100))
                    : Math.round(monDelegate.currentScale * 100)
                backgroundColor: ThemeBackend.surface0
                accentColor: ThemeBackend.mauve
                handleColor: ThemeBackend.text
                handleBorderColor: ThemeBackend.mantle
                onMoved: function(val) {
                    let rounded = Math.round(val);
                    let scaleVal = rounded / 100.0;
                    if (Math.abs(monDelegate.currentScale - scaleVal) > 0.001) {
                        monDelegate.currentScale = scaleVal;
                        monDelegate.tab.pendingMonScaleName = monDelegate.monName;
                        monDelegate.tab.pendingMonScaleVal = scaleVal;
                        monDelegate.tab.scaleDebounceTimer.restart();
                    }
                }
                onDragFinished: {
                    monDelegate.tab.scaleDebounceTimer.stop();
                    if (monDelegate.tab.pendingMonScaleName !== "") {
                        monDelegate.tab.applyMonitorScale(monDelegate.tab.pendingMonScaleName, monDelegate.tab.pendingMonScaleVal);
                        monDelegate.tab.updateMonitorSetting(monDelegate.tab.pendingMonScaleName, "scale", monDelegate.tab.pendingMonScaleVal);
                        monDelegate.tab.pendingMonScaleName = "";
                    }
                }
            }
        }
    }
}
