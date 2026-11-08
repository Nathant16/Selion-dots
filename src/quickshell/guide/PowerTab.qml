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

    // Battery and Power State
    property bool hasBattery: false
    property int capacity: 0
    property string status: "Unknown"
    property real powerWatts: 0.0
    property string timeRemainingStr: ""
    property int timeRemainingSeconds: 0
    property string activeProfile: "balanced" // "power-saver", "balanced", "performance"
    property string governor: "powersave"
    property bool boost: false
    property string gpuDpm: "auto"
    property int screenBrightness: 100
    property int thresholdStart: 95
    property int thresholdEnd: 100
    property bool hasThresholdSupport: false
    property bool conservationMode: false
    property real healthPct: 100.0
    property real energyNowWh: 0.0
    property real energyFullWh: 0.0
    property real energyDesignWh: 0.0
    property int cycles: 0

    property bool refreshing: false

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

    // Backend process for reading JSON status
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
                    powerTabRoot.timeRemainingSeconds = Number(d.time_seconds) || 0;
                    
                    let prof = String(d.profile || "").toLowerCase();
                    if (prof === "low-power") prof = "power-saver";
                    powerTabRoot.activeProfile = prof || "balanced";

                    powerTabRoot.governor = String(d.governor || "powersave");
                    powerTabRoot.boost = Boolean(d.boost);
                    powerTabRoot.gpuDpm = String(d.gpu_dpm || "auto");
                    powerTabRoot.screenBrightness = Number(d.brightness) || 100;
                    powerTabRoot.thresholdStart = Number(d.threshold_start) || 0;
                    powerTabRoot.thresholdEnd = Number(d.threshold_end) || 100;
                    powerTabRoot.hasThresholdSupport = Boolean(d.has_threshold_support);
                    powerTabRoot.conservationMode = Boolean(d.is_conservation_mode || powerTabRoot.thresholdEnd <= 80);
                    powerTabRoot.healthPct = Number(d.health_pct) || 100.0;
                    powerTabRoot.energyNowWh = Number(d.energy_now_wh) || 0.0;
                    powerTabRoot.energyFullWh = Number(d.energy_full_wh) || 0.0;
                    powerTabRoot.energyDesignWh = Number(d.energy_design_wh) || 0.0;
                    powerTabRoot.cycles = Number(d.cycles) || 0;
                } catch(e) {}
            }
        }
    }

    // Backend process for executing commands
    Process {
        id: cmdProc
        running: false
        onExited: {
            powerTabRoot.refresh();
        }
    }

    // Polling timer
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
        contentHeight: mainCol.implicitHeight + rootObj.s(24)
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
            id: mainCol
            width: parent.width - (parent.contentHeight > parent.height ? rootObj.s(6) : 0)
            spacing: rootObj.s(8)

            // 1. Live Battery Monitor Banner Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: monitorCol.implicitHeight + rootObj.s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.45)
                border.width: 1
                border.color: Qt.alpha(ThemeBackend.surface2, 0.3)

                ColumnLayout {
                    id: monitorCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: rootObj.s(12)
                    spacing: rootObj.s(12)

                    // Header row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(12)

                        // Battery state icon container
                        Rectangle {
                            implicitWidth: rootObj.s(48)
                            implicitHeight: rootObj.s(48)
                            radius: rootObj.s(12)
                            color: {
                                if (powerTabRoot.status === "Charging") return Qt.alpha(ThemeBackend.green, 0.18);
                                if (powerTabRoot.capacity <= 20) return Qt.alpha(ThemeBackend.red, 0.18);
                                return Qt.alpha(ThemeBackend.mauve, 0.18);
                            }
                            border.width: 1
                            border.color: {
                                if (powerTabRoot.status === "Charging") return Qt.alpha(ThemeBackend.green, 0.4);
                                if (powerTabRoot.capacity <= 20) return Qt.alpha(ThemeBackend.red, 0.4);
                                return Qt.alpha(ThemeBackend.mauve, 0.4);
                            }

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (powerTabRoot.status === "Charging") return "󰂄";
                                    if (powerTabRoot.status === "Full") return "󰁹";
                                    if (!powerTabRoot.hasBattery) return "󰚥";
                                    if (powerTabRoot.capacity > 80) return "󰁹";
                                    if (powerTabRoot.capacity > 60) return "󰂁";
                                    if (powerTabRoot.capacity > 40) return "󰁿";
                                    if (powerTabRoot.capacity > 20) return "󰁽";
                                    return "󰁺";
                                }
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: rootObj.s(26)
                                color: {
                                    if (powerTabRoot.status === "Charging") return ThemeBackend.green;
                                    if (powerTabRoot.capacity <= 20) return ThemeBackend.red;
                                    return ThemeBackend.mauve;
                                }
                            }
                        }

                        // Percentage, status, and power draw
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)

                            RowLayout {
                                spacing: rootObj.s(8)

                                Text {
                                    text: powerTabRoot.hasBattery ? (powerTabRoot.capacity + "%") : I18n.t("guide.power.header.status_ac", "Питание от сети")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(18)
                                    font.bold: true
                                    color: ThemeBackend.text
                                }

                                // Status pill badge
                                Rectangle {
                                    implicitHeight: rootObj.s(20)
                                    implicitWidth: statusText.implicitWidth + rootObj.s(12)
                                    radius: rootObj.s(10)
                                    color: {
                                        if (powerTabRoot.status === "Charging") return Qt.alpha(ThemeBackend.green, 0.2);
                                        if (powerTabRoot.status === "Full") return Qt.alpha(ThemeBackend.sapphire, 0.2);
                                        if (powerTabRoot.status === "Discharging") return Qt.alpha(ThemeBackend.peach, 0.2);
                                        return Qt.alpha(ThemeBackend.surface1, 0.5);
                                    }

                                    Text {
                                        id: statusText
                                        anchors.centerIn: parent
                                        text: {
                                            if (powerTabRoot.status === "Charging") return I18n.t("guide.power.header.status_charging", "Зарядка");
                                            if (powerTabRoot.status === "Discharging") return I18n.t("guide.power.header.status_discharging", "Разрядка");
                                            if (powerTabRoot.status === "Full") return I18n.t("guide.power.header.status_full", "Полностью заряжен");
                                            return I18n.t("guide.power.header.status_ac", "От сети");
                                        }
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(10)
                                        font.bold: true
                                        color: {
                                            if (powerTabRoot.status === "Charging") return ThemeBackend.green;
                                            if (powerTabRoot.status === "Full") return ThemeBackend.sapphire;
                                            if (powerTabRoot.status === "Discharging") return ThemeBackend.peach;
                                            return ThemeBackend.text;
                                        }
                                    }
                                }

                                // Power consumption badge (Watts)
                                Rectangle {
                                    visible: powerTabRoot.hasBattery && powerTabRoot.powerWatts > 0.05
                                    implicitHeight: rootObj.s(20)
                                    implicitWidth: wattsText.implicitWidth + rootObj.s(12)
                                    radius: rootObj.s(10)
                                    color: {
                                        if (powerTabRoot.powerWatts < 8.0) return Qt.alpha(ThemeBackend.green, 0.15);
                                        if (powerTabRoot.powerWatts < 15.0) return Qt.alpha(ThemeBackend.yellow, 0.15);
                                        return Qt.alpha(ThemeBackend.red, 0.15);
                                    }

                                    Text {
                                        id: wattsText
                                        anchors.centerIn: parent
                                        text: "⚡ " + I18n.t("guide.power.header.watts", "{w} Вт").replace("{w}", powerTabRoot.powerWatts.toFixed(2))
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(10)
                                        font.bold: true
                                        color: {
                                            if (powerTabRoot.powerWatts < 8.0) return ThemeBackend.green;
                                            if (powerTabRoot.powerWatts < 15.0) return ThemeBackend.yellow;
                                            return ThemeBackend.red;
                                        }
                                    }
                                }
                            }

                            // Subtitle: Time remaining or AC status
                            Text {
                                visible: powerTabRoot.hasBattery
                                text: powerTabRoot.timeRemainingStr ? powerTabRoot.timeRemainingStr : (powerTabRoot.status === "Full" ? I18n.t("guide.power.header.status_full", "Полностью заряжен") : "")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                color: ThemeBackend.subtext0
                            }
                        }

                        // Manual Refresh button
                        IconButton {
                            size: rootObj.s(34)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonIcon: "󰑐"
                            iconFontSize: rootObj.s(15)
                            accentColor: ThemeBackend.surface1
                            textColor: ThemeBackend.text
                            onClicked: powerTabRoot.refresh()
                        }
                    }

                    // Battery Level Progress Bar
                    Rectangle {
                        visible: powerTabRoot.hasBattery
                        Layout.fillWidth: true
                        implicitHeight: rootObj.s(8)
                        radius: rootObj.s(4)
                        color: ThemeBackend.surface1
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * (Math.max(0, Math.min(100, powerTabRoot.capacity)) / 100.0)
                            radius: rootObj.s(4)
                            color: {
                                if (powerTabRoot.status === "Charging") return ThemeBackend.green;
                                if (powerTabRoot.capacity > 50) return ThemeBackend.green;
                                if (powerTabRoot.capacity > 20) return ThemeBackend.yellow;
                                return ThemeBackend.red;
                            }

                            Behavior on width {
                                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    // Metric chips row (Health, Capacity Wh, Cycles)
                    RowLayout {
                        visible: powerTabRoot.hasBattery
                        Layout.fillWidth: true
                        spacing: rootObj.s(8)

                        // Health chip
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(32)
                            radius: rootObj.s(8)
                            color: Qt.alpha(ThemeBackend.surface1, 0.4)

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: rootObj.s(4)

                                Text {
                                    text: "󰟢"
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: rootObj.s(13)
                                    color: ThemeBackend.mauve
                                }

                                Text {
                                    text: I18n.t("guide.power.header.health", "Здоровье: {val}%").replace("{val}", powerTabRoot.healthPct.toFixed(1))
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                    color: ThemeBackend.text
                                }
                            }
                        }

                        // Capacity Wh chip
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(32)
                            radius: rootObj.s(8)
                            color: Qt.alpha(ThemeBackend.surface1, 0.4)

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: rootObj.s(4)

                                Text {
                                    text: "󰚥"
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: rootObj.s(13)
                                    color: ThemeBackend.sapphire
                                }

                                Text {
                                    text: I18n.t("guide.power.header.capacity_wh", "{now} / {full} Вт·ч").replace("{now}", powerTabRoot.energyNowWh.toFixed(1)).replace("{full}", powerTabRoot.energyFullWh.toFixed(1))
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                    color: ThemeBackend.text
                                }
                            }
                        }

                        // Cycles chip
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(32)
                            radius: rootObj.s(8)
                            color: Qt.alpha(ThemeBackend.surface1, 0.4)

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: rootObj.s(4)

                                Text {
                                    text: "󰑐"
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: rootObj.s(13)
                                    color: ThemeBackend.peach
                                }

                                Text {
                                    text: I18n.t("guide.power.header.cycles", "{count} циклов").replace("{count}", powerTabRoot.cycles)
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                    color: ThemeBackend.text
                                }
                            }
                        }
                    }
                }
            }

            // 2. Power Profiles Selector
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: profilesCol.implicitHeight + rootObj.s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.45)
                border.width: 1
                border.color: Qt.alpha(ThemeBackend.surface2, 0.3)

                ColumnLayout {
                    id: profilesCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: rootObj.s(12)
                    spacing: rootObj.s(12)

                    // Header
                    RowLayout {
                        spacing: rootObj.s(8)

                        Text {
                            text: "󰌪"
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: rootObj.s(18)
                            color: ThemeBackend.mauve
                        }

                        ColumnLayout {
                            spacing: rootObj.s(1)

                            Text {
                                text: I18n.t("guide.power.profiles.title", "Профиль энергопотребления")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(13)
                                font.bold: true
                                color: ThemeBackend.text
                            }

                            Text {
                                text: I18n.t("guide.power.profiles.desc", "Выберите режим работы процессора, видеокарты и вентиляторов")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                color: ThemeBackend.subtext0
                            }
                        }
                    }

                    // 3 Profile Cards (Power Saver, Balanced, Performance)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(8)

                        // 1. Power Saver Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(76)
                            radius: ThemeBackend.borderRadius
                            readonly property bool active: powerTabRoot.activeProfile === "power-saver"

                            color: active ? Qt.alpha(ThemeBackend.green, 0.18) : (saverMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.6) : Qt.alpha(ThemeBackend.surface1, 0.35))
                            border.width: active ? 1.5 : 1
                            border.color: active ? ThemeBackend.green : Qt.alpha(ThemeBackend.surface2, 0.3)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: rootObj.s(8)
                                spacing: rootObj.s(3)

                                RowLayout {
                                    spacing: rootObj.s(6)
                                    Text {
                                        text: "󰌪"
                                        font.family: ThemeBackend.iconFont
                                        font.pixelSize: rootObj.s(16)
                                        color: parent.parent.parent.active ? ThemeBackend.green : ThemeBackend.subtext0
                                    }
                                    Text {
                                        text: I18n.t("guide.power.profiles.saver_title", "Энергосбережение")
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(12)
                                        font.bold: true
                                        color: parent.parent.parent.active ? ThemeBackend.green : ThemeBackend.text
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.t("guide.power.profiles.saver_desc", "Мин. расход (~5-8 Вт). Без Boost")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(10)
                                    color: ThemeBackend.subtext0
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                }
                            }

                            MouseArea {
                                id: saverMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: powerTabRoot.setProfile("power-saver")
                            }
                        }

                        // 2. Balanced Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(76)
                            radius: ThemeBackend.borderRadius
                            readonly property bool active: powerTabRoot.activeProfile === "balanced"

                            color: active ? Qt.alpha(ThemeBackend.mauve, 0.18) : (balMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.6) : Qt.alpha(ThemeBackend.surface1, 0.35))
                            border.width: active ? 1.5 : 1
                            border.color: active ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.surface2, 0.3)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: rootObj.s(8)
                                spacing: rootObj.s(3)

                                RowLayout {
                                    spacing: rootObj.s(6)
                                    Text {
                                        text: "󰓅"
                                        font.family: ThemeBackend.iconFont
                                        font.pixelSize: rootObj.s(16)
                                        color: parent.parent.parent.active ? ThemeBackend.mauve : ThemeBackend.subtext0
                                    }
                                    Text {
                                        text: I18n.t("guide.power.profiles.balanced_title", "Сбалансированный")
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(12)
                                        font.bold: true
                                        color: parent.parent.parent.active ? ThemeBackend.mauve : ThemeBackend.text
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.t("guide.power.profiles.balanced_desc", "Оптимально для повседневных задач")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(10)
                                    color: ThemeBackend.subtext0
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                }
                            }

                            MouseArea {
                                id: balMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: powerTabRoot.setProfile("balanced")
                            }
                        }

                        // 3. Performance Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(76)
                            radius: ThemeBackend.borderRadius
                            readonly property bool active: powerTabRoot.activeProfile === "performance"

                            color: active ? Qt.alpha(ThemeBackend.peach, 0.18) : (perfMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.6) : Qt.alpha(ThemeBackend.surface1, 0.35))
                            border.width: active ? 1.5 : 1
                            border.color: active ? ThemeBackend.peach : Qt.alpha(ThemeBackend.surface2, 0.3)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: rootObj.s(8)
                                spacing: rootObj.s(3)

                                RowLayout {
                                    spacing: rootObj.s(6)
                                    Text {
                                        text: "󰓅"
                                        font.family: ThemeBackend.iconFont
                                        font.pixelSize: rootObj.s(16)
                                        color: parent.parent.parent.active ? ThemeBackend.peach : ThemeBackend.subtext0
                                    }
                                    Text {
                                        text: I18n.t("guide.power.profiles.perf_title", "Производительность")
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(12)
                                        font.bold: true
                                        color: parent.parent.parent.active ? ThemeBackend.peach : ThemeBackend.text
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.t("guide.power.profiles.perf_desc", "Максимальная частота ядер и Boost")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(10)
                                    color: ThemeBackend.subtext0
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                }
                            }

                            MouseArea {
                                id: perfMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: powerTabRoot.setProfile("performance")
                            }
                        }
                    }
                }
            }

            // 3. Battery Protection (Charge Limit Threshold) Group
            SettingsGroup {
                visible: powerTabRoot.hasThresholdSupport
                rootObj: powerTabRoot.rootObj
                icon: "󰂃"
                title: I18n.t("guide.power.threshold.title", "Защита аккумулятора (порог заряда)")
                description: I18n.t("guide.power.threshold.desc", "Ограничение уровня заряда до 80% продлевает срок службы батареи на годы")
                expanded: true

                Toggle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    checked: powerTabRoot.conservationMode
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface1
                    handleColor: ThemeBackend.crust
                    handleOffColor: ThemeBackend.text
                    onToggled: function(c) {
                        powerTabRoot.setLimit(c ? 80 : 100);
                    }
                }

                subSettings: [
                    // Explanatory hint banner
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: hintCol.implicitHeight + rootObj.s(16)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.surface1, 0.25)

                        ColumnLayout {
                            id: hintCol
                            anchors.fill: parent
                            anchors.margins: rootObj.s(10)
                            spacing: rootObj.s(4)

                            RowLayout {
                                spacing: rootObj.s(6)
                                Text {
                                    text: "󰋼"
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: rootObj.s(14)
                                    color: ThemeBackend.mauve
                                }
                                Text {
                                    text: powerTabRoot.conservationMode
                                        ? I18n.t("guide.power.threshold.conservation_active", "Режим защиты активен (зарядка до 80%)")
                                        : I18n.t("guide.power.threshold.full_active", "Режим максимального заряда (до 100%)")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(12)
                                    font.bold: true
                                    color: powerTabRoot.conservationMode ? ThemeBackend.green : ThemeBackend.sapphire
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: I18n.t("guide.power.threshold.hint", "При частой работе от сети постоянный заряд на 100% ускоряет деградацию аккумулятора. Режим 80% сохраняет химический ресурс ячеек.")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(10.5)
                                color: ThemeBackend.subtext0
                                wrapMode: Text.Wrap
                            }
                        }
                    },

                    // Quick Switch Buttons (80% Conservation vs 100% Full)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(8)

                        ClickButton {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(32)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonText: I18n.t("guide.power.threshold.btn_conservation", "Защита батареи (80%)")
                            buttonIcon: "󰂃"
                            iconFontSize: rootObj.s(14)
                            textFontSize: rootObj.s(11.5)
                            accentColor: powerTabRoot.thresholdEnd === 80 ? ThemeBackend.mauve : ThemeBackend.surface1
                            textColor: powerTabRoot.thresholdEnd === 80 ? ThemeBackend.crust : ThemeBackend.text
                            onClicked: powerTabRoot.setLimit(80)
                        }

                        ClickButton {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(32)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonText: I18n.t("guide.power.threshold.btn_full", "Полный заряд (100%)")
                            buttonIcon: "󰁹"
                            iconFontSize: rootObj.s(14)
                            textFontSize: rootObj.s(11.5)
                            accentColor: powerTabRoot.thresholdEnd === 100 ? ThemeBackend.sapphire : ThemeBackend.surface1
                            textColor: powerTabRoot.thresholdEnd === 100 ? ThemeBackend.crust : ThemeBackend.text
                            onClicked: powerTabRoot.setLimit(100)
                        }
                    },

                    // Custom Limit NumberSelector Row
                    SettingsRow {
                        rootObj: powerTabRoot.rootObj
                        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                        icon: "󰚥"
                        title: I18n.t("guide.power.threshold.custom_label", "Пользовательский лимит заряда")
                        description: I18n.t("guide.power.threshold.custom_desc", "Уровень заряда, при котором прекращается подача питания на батарею")

                        NumberSelector {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: rootObj.s(120)
                            implicitHeight: rootObj.s(32)
                            from: 40
                            to: 100
                            stepSize: 5
                            decimals: 0
                            value: powerTabRoot.thresholdEnd
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
                            onValueChanged: {
                                let v = Math.round(value);
                                if (!isNaN(v) && v >= 40 && v <= 100 && powerTabRoot.thresholdEnd !== v) {
                                    powerTabRoot.setLimit(v);
                                }
                            }
                        }
                    }
                ]
            }

            // 4. Hardware Parameters & Tuning Group
            SettingsGroup {
                rootObj: powerTabRoot.rootObj
                icon: "󰒓"
                title: I18n.t("guide.power.hardware.title", "Аппаратные параметры")
                description: I18n.t("guide.power.hardware.desc", "Текущее состояние регуляторов CPU, Turbo Boost и GPU")
                expanded: false

                subSettings: [
                    // CPU Governor
                    SettingsRow {
                        rootObj: powerTabRoot.rootObj
                        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                        icon: "󰍛"
                        title: I18n.t("guide.power.hardware.governor", "Регулятор частоты CPU")
                        description: "Energy Performance Preference (EPP)"

                        Rectangle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitHeight: rootObj.s(26)
                            implicitWidth: govLabel.implicitWidth + rootObj.s(14)
                            radius: rootObj.s(6)
                            color: ThemeBackend.surface1

                            Text {
                                id: govLabel
                                anchors.centerIn: parent
                                text: powerTabRoot.governor
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                font.bold: true
                                color: ThemeBackend.text
                            }
                        }
                    },

                    // CPU Boost
                    SettingsRow {
                        rootObj: powerTabRoot.rootObj
                        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                        icon: "󰓅"
                        title: I18n.t("guide.power.hardware.boost", "Turbo Boost процессора")
                        description: powerTabRoot.boost ? "Повышенные частоты ядер" : "Энергоэффективная базовая частота"

                        Rectangle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitHeight: rootObj.s(26)
                            implicitWidth: boostLabel.implicitWidth + rootObj.s(14)
                            radius: rootObj.s(6)
                            color: powerTabRoot.boost ? Qt.alpha(ThemeBackend.peach, 0.25) : Qt.alpha(ThemeBackend.green, 0.25)

                            Text {
                                id: boostLabel
                                anchors.centerIn: parent
                                text: powerTabRoot.boost ? I18n.t("guide.power.hardware.boost_on", "ВКЛ") : I18n.t("guide.power.hardware.boost_off", "ВЫКЛ")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                font.bold: true
                                color: powerTabRoot.boost ? ThemeBackend.peach : ThemeBackend.green
                            }
                        }
                    },

                    // GPU DPM
                    SettingsRow {
                        rootObj: powerTabRoot.rootObj
                        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                        icon: "󰢮"
                        title: I18n.t("guide.power.hardware.gpu_dpm", "Режим энергопотребления GPU")
                        description: "Dynamic Power Management (DPM)"

                        Rectangle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitHeight: rootObj.s(26)
                            implicitWidth: gpuLabel.implicitWidth + rootObj.s(14)
                            radius: rootObj.s(6)
                            color: ThemeBackend.surface1

                            Text {
                                id: gpuLabel
                                anchors.centerIn: parent
                                text: powerTabRoot.gpuDpm
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                font.bold: true
                                color: ThemeBackend.text
                            }
                        }
                    },

                    // Display Brightness & Energy Tip
                    SettingsRow {
                        rootObj: powerTabRoot.rootObj
                        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                        icon: "󰃠"
                        title: I18n.t("guide.power.hardware.brightness", "Яркость дисплея")
                        description: I18n.t("guide.power.hardware.brightness_hint", "Снижение яркости экрана до ~35-40% экономит до 2 Вт энергии")

                        Rectangle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitHeight: rootObj.s(26)
                            implicitWidth: blLabel.implicitWidth + rootObj.s(14)
                            radius: rootObj.s(6)
                            color: ThemeBackend.surface1

                            Text {
                                id: blLabel
                                anchors.centerIn: parent
                                text: powerTabRoot.screenBrightness + "%"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                font.bold: true
                                color: ThemeBackend.text
                            }
                        }
                    }
                ]
            }

            // 5. Sleep & Timeout Settings Link
            SettingsBlob {
                SettingsRow {
                    rootObj: powerTabRoot.rootObj
                    icon: "󰒲"
                    title: I18n.t("guide.power.idle_link.title", "Тайм-ауты сна и дисплея")
                    description: I18n.t("guide.power.idle_link.desc", "Настройка автоматического выключения экрана (DPMS) и перехода в спящий режим")

                    ClickButton {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitHeight: rootObj.s(32)
                        horizontalPadding: rootObj.s(12)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonText: I18n.t("guide.power.idle_link.button", "Настроить тайм-ауты...")
                        buttonIcon: "󰒲"
                        iconFontSize: rootObj.s(14)
                        textFontSize: rootObj.s(11)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: {
                            if (powerTabRoot.rootObj && typeof powerTabRoot.rootObj.gotoTab === "function") {
                                powerTabRoot.rootObj.gotoTab("idle");
                            }
                        }
                    }
                }
            }
        }
    }
}

