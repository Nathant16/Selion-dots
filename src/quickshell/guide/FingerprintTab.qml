import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

GuideTab {
    id: fingerprintTabRoot

    property var defaultLockscreenSettings: ({
        "fingerprintEnabled": true,
        "attemptLimitEnabled": false,
        "passwordMaxAttempts": 5,
        "fingerprintMaxAttempts": 5,
        "backgroundMode": "follow",
        "customBackground": ""
    })

    property var lockscreenSettings: {
        let s = (typeof Config !== "undefined" && Config.rawSettings) ? Config.rawSettings["lockscreen"] : undefined;
        if (s !== undefined && s !== null) return s;
        if (typeof Config !== "undefined" && typeof Config.getSetting === "function") {
            return Config.getSetting("lockscreen", fingerprintTabRoot.defaultLockscreenSettings);
        }
        return fingerprintTabRoot.defaultLockscreenSettings;
    }

    property bool currentFingerprintEnabled: lockscreenSettings && lockscreenSettings.fingerprintEnabled !== false
    property bool currentAttemptLimitEnabled: lockscreenSettings && lockscreenSettings.attemptLimitEnabled === true
    property int currentFingerprintMaxAttempts: (lockscreenSettings && lockscreenSettings.fingerprintMaxAttempts !== undefined) ? Number(lockscreenSettings.fingerprintMaxAttempts) : 5

    // Hardware and backend state
    property bool hardwareAvailable: false
    property string deviceName: ""
    property string scanType: "press"
    property int enrollStages: 9
    property var enrolledFingers: []

    // Enrollment selection state
    property string selectedHand: "right" // "right" or "left"
    property string selectedFingerType: "index-finger" // "thumb", "index-finger", "middle-finger", "ring-finger", "little-finger"
    readonly property string targetFingerName: selectedHand + "-" + selectedFingerType
    readonly property bool isTargetEnrolled: enrolledFingers.indexOf(targetFingerName) !== -1

    // Active enrollment process state
    property bool isEnrolling: false
    property int currentStage: 0
    property int currentPercent: 0
    property string enrollStatus: "ready" // "ready", "stage_passed", "retry_scan", "completed", "failed"
    property string enrollMessage: ""

    readonly property string scriptPath: (typeof Caching !== "undefined" && Caching.serpantinumDir)
        ? (Caching.serpantinumDir + "/scripts/system/fingerprint_manager.sh")
        : "fingerprint_manager.sh"

    function syncSettings() {
        let s = (typeof Config !== "undefined" && typeof Config.getSetting === "function")
            ? Config.getSetting("lockscreen", fingerprintTabRoot.defaultLockscreenSettings)
            : fingerprintTabRoot.defaultLockscreenSettings;
        fingerprintTabRoot.lockscreenSettings = s;
        fingerprintTabRoot.currentFingerprintEnabled = s.fingerprintEnabled !== false;
        fingerprintTabRoot.currentAttemptLimitEnabled = s.attemptLimitEnabled === true;
        fingerprintTabRoot.currentFingerprintMaxAttempts = s.fingerprintMaxAttempts !== undefined ? Number(s.fingerprintMaxAttempts) : 5;
    }

    function updateLockscreenSetting(key, value) {
        let current = JSON.parse(JSON.stringify((typeof Config !== "undefined" && typeof Config.getSetting === "function")
            ? (Config.getSetting("lockscreen", defaultLockscreenSettings) || defaultLockscreenSettings)
            : defaultLockscreenSettings));
        current[key] = value;
        if (typeof Config !== "undefined" && typeof Config.setSetting === "function") {
            Config.setSetting("lockscreen", current);
        }
        fingerprintTabRoot.lockscreenSettings = current;
    }

    function refreshHardware() {
        probeProcess.running = false;
        probeProcess.running = true;
        listProcess.running = false;
        listProcess.running = true;
    }

    function getFingerLabel(fingerId) {
        return I18n.t("guide.fingerprint.fingers." + fingerId, fingerId);
    }

    function getShortFingerLabel(type) {
        return I18n.t("guide.fingerprint.finger_short." + type, type);
    }

    function startEnrollment() {
        if (isTargetEnrolled) return;
        currentStage = 0;
        currentPercent = 0;
        enrollStatus = "ready";
        enrollMessage = I18n.t("guide.fingerprint.enroll.place_finger", "Приложите палец к сканеру");
        isEnrolling = true;
        enrollProcess.command = ["bash", fingerprintTabRoot.scriptPath, "enroll", targetFingerName];
        enrollProcess.running = true;
    }

    function cancelEnrollment() {
        if (enrollProcess.running) {
            enrollProcess.running = false;
        }
        isEnrolling = false;
        enrollStatus = "ready";
    }

    function deleteFinger(finger) {
        deleteProcess.command = ["bash", fingerprintTabRoot.scriptPath, "delete", finger];
        deleteProcess.running = true;
    }

    function deleteAllFingers() {
        deleteProcess.command = ["bash", fingerprintTabRoot.scriptPath, "delete", "all"];
        deleteProcess.running = true;
    }

    // Backend processes
    Process {
        id: probeProcess
        command: ["bash", fingerprintTabRoot.scriptPath, "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text);
                    fingerprintTabRoot.hardwareAvailable = Boolean(data.available);
                    if (data.device) fingerprintTabRoot.deviceName = data.device;
                    if (data.scan_type) fingerprintTabRoot.scanType = data.scan_type;
                    if (data.stages) fingerprintTabRoot.enrollStages = Number(data.stages) || 9;
                } catch(e) {}
            }
        }
    }

    Process {
        id: listProcess
        command: ["bash", fingerprintTabRoot.scriptPath, "list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text);
                    if (data.fingers && Array.isArray(data.fingers)) {
                        fingerprintTabRoot.enrolledFingers = data.fingers;
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: deleteProcess
        running: false
        onExited: {
            listProcess.running = true;
        }
    }

    Process {
        id: enrollProcess
        running: false
        stdout: SplitParser {
            onRead: (raw) => {
                let line = String(raw || "").trim();
                if (!line) return;
                try {
                    let msg = JSON.parse(line);
                    if (msg.type === "started") {
                        fingerprintTabRoot.currentStage = 0;
                        fingerprintTabRoot.currentPercent = 0;
                        fingerprintTabRoot.enrollStatus = "ready";
                        fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.place_finger", "Приложите палец к сканеру");
                    } else if (msg.type === "progress") {
                        fingerprintTabRoot.currentStage = msg.stage || 0;
                        fingerprintTabRoot.currentPercent = msg.percent || 0;
                        fingerprintTabRoot.enrollStatus = msg.status || "stage_passed";
                        if (msg.status === "stage_passed") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.step_passed", "Отлично! Поднимите палец и приложите снова");
                        } else if (msg.status === "retry_scan") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.retry", "Не удалось распознать. Попробуйте снова");
                        } else if (msg.status === "swipe_too_short") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.swipe_too_short", "Слишком короткое движение. Проведите медленнее");
                        } else if (msg.status === "not_centered") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.not_centered", "Приложите палец ближе к центру сканера");
                        } else if (msg.status === "remove_retry") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.remove_retry", "Снимите палец и приложите заново");
                        } else if (msg.message) {
                            fingerprintTabRoot.enrollMessage = msg.message;
                        }
                    } else if (msg.type === "completed") {
                        fingerprintTabRoot.currentStage = fingerprintTabRoot.enrollStages;
                        fingerprintTabRoot.currentPercent = 100;
                        fingerprintTabRoot.enrollStatus = "completed";
                        fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.success", "Отпечаток успешно добавлен!");
                        listProcess.running = true;
                    } else if (msg.type === "failed") {
                        fingerprintTabRoot.enrollStatus = "failed";
                        fingerprintTabRoot.enrollMessage = msg.message || I18n.t("guide.fingerprint.enroll.failed", "Не удалось зарегистрировать отпечаток");
                    } else if (msg.type === "finished") {
                        if (msg.success) {
                            listProcess.running = true;
                        }
                    }
                } catch(e) {}
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            syncSettings();
            refreshHardware();
        } else {
            if (fingerprintTabRoot.isEnrolling) {
                cancelEnrollment();
            }
        }
    }

    Component.onCompleted: {
        syncSettings();
        refreshHardware();
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            fingerprintTabRoot.syncSettings();
        }
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

            // 1. Hardware Status Card Banner
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: bannerRow.implicitHeight + rootObj.s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.45)
                border.width: 1
                border.color: Qt.alpha(ThemeBackend.surface2, 0.3)

                RowLayout {
                    id: bannerRow
                    anchors.fill: parent
                    anchors.margins: rootObj.s(12)
                    spacing: rootObj.s(14)

                    // Sensor icon circle
                    Rectangle {
                        implicitWidth: rootObj.s(48)
                        implicitHeight: rootObj.s(48)
                        radius: rootObj.s(12)
                        color: fingerprintTabRoot.hardwareAvailable ? Qt.alpha(ThemeBackend.mauve, 0.15) : Qt.alpha(ThemeBackend.surface1, 0.5)
                        border.width: 1
                        border.color: fingerprintTabRoot.hardwareAvailable ? Qt.alpha(ThemeBackend.mauve, 0.4) : Qt.alpha(ThemeBackend.surface2, 0.4)

                        Text {
                            anchors.centerIn: parent
                            text: "󰈷"
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: rootObj.s(24)
                            color: fingerprintTabRoot.hardwareAvailable ? ThemeBackend.mauve : ThemeBackend.subtext0
                        }
                    }

                    // Device details
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)

                        Text {
                            Layout.fillWidth: true
                            text: fingerprintTabRoot.hardwareAvailable
                                ? (fingerprintTabRoot.deviceName || I18n.t("guide.fingerprint.header.title", "Сканер отпечатков пальцев"))
                                : I18n.t("guide.fingerprint.header.not_found", "Сканер не обнаружен")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(14)
                            font.bold: true
                            color: ThemeBackend.text
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            spacing: rootObj.s(6)

                            // Status dot
                            Rectangle {
                                implicitWidth: rootObj.s(8)
                                implicitHeight: rootObj.s(8)
                                radius: rootObj.s(4)
                                color: fingerprintTabRoot.hardwareAvailable ? ThemeBackend.green : ThemeBackend.red
                            }

                            Text {
                                text: fingerprintTabRoot.hardwareAvailable
                                    ? (I18n.t("guide.fingerprint.header.ready", "Сканер готов к работе") + " • " +
                                       (fingerprintTabRoot.scanType === "press"
                                            ? I18n.t("guide.fingerprint.header.touch_type", "Касание")
                                            : I18n.t("guide.fingerprint.header.swipe_type", "Проведение")) + " • " +
                                       I18n.t("guide.fingerprint.header.stages_count", "Шагов: {count}").replace("{count}", fingerprintTabRoot.enrollStages))
                                    : I18n.t("guide.fingerprint.header.not_found_desc", "Биометрический сканер не найден в системе")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                color: ThemeBackend.subtext0
                            }
                        }
                    }

                    // Refresh Button
                    IconButton {
                        id: refreshBtn
                        size: rootObj.s(34)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonIcon: "󰑐"
                        iconFontSize: rootObj.s(15)
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: fingerprintTabRoot.refreshHardware()
                    }
                }
            }

            // 2. Master Switch (Enable / Disable fingerprint login)
            SettingsBlob {
                SettingsRow {
                    rootObj: fingerprintTabRoot.rootObj
                    icon: "󰈷"
                    iconAccentColor: ThemeBackend.mauve
                    iconTextColor: ThemeBackend.crust
                    title: I18n.t("guide.fingerprint.master.title", "Использовать отпечатки пальцев")
                    description: I18n.t("guide.fingerprint.master.desc", "Разрешить вход в систему и разблокировку экрана по отпечатку")
                    settingId: "fingerprint_master"
                    searchKeywords: "fingerprint biometric fprintd отпечаток палец вход биометрия"

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: fingerprintTabRoot.currentFingerprintEnabled
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(c) {
                            fingerprintTabRoot.currentFingerprintEnabled = c;
                            fingerprintTabRoot.updateLockscreenSetting("fingerprintEnabled", c);
                        }
                    }
                }
            }

            // 3. Interactive Fingerprint Enrollment Card
            Rectangle {
                visible: fingerprintTabRoot.hardwareAvailable
                Layout.fillWidth: true
                implicitHeight: enrollCol.implicitHeight + rootObj.s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.45)
                border.width: 1
                border.color: Qt.alpha(ThemeBackend.surface2, 0.3)
                clip: true

                ColumnLayout {
                    id: enrollCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: rootObj.s(12)
                    spacing: rootObj.s(12)

                    // Card header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(10)

                        Rectangle {
                            implicitWidth: rootObj.s(32)
                            implicitHeight: rootObj.s(32)
                            radius: rootObj.s(8)
                            color: Qt.alpha(ThemeBackend.mauve, 0.2)

                            Text {
                                anchors.centerIn: parent
                                text: fingerprintTabRoot.isEnrolling ? "󰐰" : "󰐕"
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: rootObj.s(16)
                                color: ThemeBackend.mauve
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(1)

                            Text {
                                text: fingerprintTabRoot.isEnrolling
                                    ? I18n.t("guide.fingerprint.enroll.active_title", "Сканирование: {finger}").replace("{finger}", fingerprintTabRoot.getFingerLabel(fingerprintTabRoot.targetFingerName))
                                    : I18n.t("guide.fingerprint.enroll.title", "Добавить отпечаток")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(13)
                                font.bold: true
                                color: ThemeBackend.text
                            }

                            Text {
                                text: fingerprintTabRoot.isEnrolling
                                    ? (fingerprintTabRoot.currentPercent + "% • " + I18n.t("guide.fingerprint.enroll.step", "Шаг {current} из {total}").replace("{current}", fingerprintTabRoot.currentStage).replace("{total}", fingerprintTabRoot.enrollStages))
                                    : I18n.t("guide.fingerprint.enroll.desc", "Выберите палец и выполните сканирование на датчике")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                color: ThemeBackend.subtext0
                            }
                        }
                    }

                    // --- VIEW 1: SELECTOR (when not enrolling) ---
                    ColumnLayout {
                        visible: !fingerprintTabRoot.isEnrolling
                        Layout.fillWidth: true
                        spacing: rootObj.s(10)

                        // Hand Selection Tabs
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)

                            // Left hand tab button
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: rootObj.s(32)
                                radius: ThemeBackend.borderRadius
                                color: fingerprintTabRoot.selectedHand === "left"
                                    ? Qt.alpha(ThemeBackend.mauve, 0.22)
                                    : Qt.alpha(ThemeBackend.surface1, 0.4)
                                border.width: 1
                                border.color: fingerprintTabRoot.selectedHand === "left"
                                    ? ThemeBackend.mauve
                                    : Qt.alpha(ThemeBackend.surface2, 0.3)

                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.t("guide.fingerprint.enroll.hand_left", "Левая рука")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(12)
                                    font.bold: fingerprintTabRoot.selectedHand === "left"
                                    color: fingerprintTabRoot.selectedHand === "left" ? ThemeBackend.mauve : ThemeBackend.text
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: fingerprintTabRoot.selectedHand = "left"
                                }
                            }

                            // Right hand tab button
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: rootObj.s(32)
                                radius: ThemeBackend.borderRadius
                                color: fingerprintTabRoot.selectedHand === "right"
                                    ? Qt.alpha(ThemeBackend.mauve, 0.22)
                                    : Qt.alpha(ThemeBackend.surface1, 0.4)
                                border.width: 1
                                border.color: fingerprintTabRoot.selectedHand === "right"
                                    ? ThemeBackend.mauve
                                    : Qt.alpha(ThemeBackend.surface2, 0.3)

                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.t("guide.fingerprint.enroll.hand_right", "Правая рука")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(12)
                                    font.bold: fingerprintTabRoot.selectedHand === "right"
                                    color: fingerprintTabRoot.selectedHand === "right" ? ThemeBackend.mauve : ThemeBackend.text
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: fingerprintTabRoot.selectedHand = "right"
                                }
                            }
                        }

                        // Finger Selection Buttons (Thumb, Index, Middle, Ring, Little)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)

                            Repeater {
                                model: [
                                    { id: "thumb", icon: "󰈷" },
                                    { id: "index-finger", icon: "󰈷" },
                                    { id: "middle-finger", icon: "󰈷" },
                                    { id: "ring-finger", icon: "󰈷" },
                                    { id: "little-finger", icon: "󰈷" }
                                ]

                                delegate: Rectangle {
                                    id: fingerBtn
                                    Layout.fillWidth: true
                                    implicitHeight: rootObj.s(52)
                                    radius: ThemeBackend.borderRadius

                                    readonly property string fingerKey: fingerprintTabRoot.selectedHand + "-" + modelData.id
                                    readonly property bool enrolled: fingerprintTabRoot.enrolledFingers.indexOf(fingerKey) !== -1
                                    readonly property bool selected: fingerprintTabRoot.selectedFingerType === modelData.id

                                    color: selected
                                        ? Qt.alpha(ThemeBackend.mauve, 0.2)
                                        : (fingerMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.7) : Qt.alpha(ThemeBackend.surface1, 0.35))
                                    border.width: selected ? 1.5 : 1
                                    border.color: selected
                                        ? ThemeBackend.mauve
                                        : (enrolled ? Qt.alpha(ThemeBackend.green, 0.5) : Qt.alpha(ThemeBackend.surface2, 0.3))

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: rootObj.s(2)

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: rootObj.s(4)

                                            Text {
                                                text: modelData.icon
                                                font.family: ThemeBackend.iconFont
                                                font.pixelSize: rootObj.s(15)
                                                color: enrolled ? ThemeBackend.green : (selected ? ThemeBackend.mauve : ThemeBackend.subtext0)
                                            }

                                            Text {
                                                visible: enrolled
                                                text: "󰄬"
                                                font.family: ThemeBackend.iconFont
                                                font.pixelSize: rootObj.s(12)
                                                color: ThemeBackend.green
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: fingerprintTabRoot.getShortFingerLabel(modelData.id)
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            font.bold: selected
                                            color: selected ? ThemeBackend.mauve : ThemeBackend.text
                                        }
                                    }

                                    MouseArea {
                                        id: fingerMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            fingerprintTabRoot.selectedFingerType = modelData.id;
                                        }
                                    }
                                }
                            }
                        }

                        // Enroll Action Row
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: rootObj.s(4)
                            spacing: rootObj.s(10)

                            Text {
                                Layout.fillWidth: true
                                text: fingerprintTabRoot.isTargetEnrolled
                                    ? (fingerprintTabRoot.getFingerLabel(fingerprintTabRoot.targetFingerName) + " (" + I18n.t("guide.fingerprint.enroll.already_enrolled", "Уже зарегистрирован") + ")")
                                    : fingerprintTabRoot.getFingerLabel(fingerprintTabRoot.targetFingerName)
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(12)
                                color: fingerprintTabRoot.isTargetEnrolled ? ThemeBackend.subtext0 : ThemeBackend.text
                                elide: Text.ElideRight
                            }

                            ClickButton {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                implicitHeight: rootObj.s(32)
                                horizontalPadding: rootObj.s(14)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonText: I18n.t("guide.fingerprint.enroll.button_start", "Начать сканирование")
                                buttonIcon: "󰈷"
                                iconFontSize: rootObj.s(15)
                                textFontSize: rootObj.s(12)
                                accentColor: fingerprintTabRoot.isTargetEnrolled ? ThemeBackend.surface1 : ThemeBackend.mauve
                                textColor: fingerprintTabRoot.isTargetEnrolled ? ThemeBackend.subtext0 : ThemeBackend.crust
                                enabled: !fingerprintTabRoot.isTargetEnrolled
                                onClicked: fingerprintTabRoot.startEnrollment()
                            }
                        }
                    }

                    // --- VIEW 2: LIVE ENROLLMENT ANIMATION ---
                    ColumnLayout {
                        visible: fingerprintTabRoot.isEnrolling
                        Layout.fillWidth: true
                        Layout.topMargin: rootObj.s(6)
                        Layout.bottomMargin: rootObj.s(6)
                        spacing: rootObj.s(16)

                        readonly property color activeColor: {
                            if (fingerprintTabRoot.enrollStatus === "completed") return ThemeBackend.green;
                            if (fingerprintTabRoot.enrollStatus === "failed") return ThemeBackend.red;
                            if (fingerprintTabRoot.enrollStatus === "stage_passed") return ThemeBackend.green;
                            return ThemeBackend.mauve;
                        }

                        // Animated pulsing fingerprint visual
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: rootObj.s(100)
                            implicitHeight: rootObj.s(100)

                            // Outer pulsing glow
                            Rectangle {
                                id: outerPulse
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.height
                                radius: width / 2
                                color: Qt.alpha(parent.parent.activeColor, 0.12)
                                border.width: 2
                                border.color: Qt.alpha(parent.parent.activeColor, 0.4)

                                SequentialAnimation on scale {
                                    running: fingerprintTabRoot.isEnrolling && fingerprintTabRoot.enrollStatus !== "completed"
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.94; to: 1.06; duration: 900; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1.06; to: 0.94; duration: 900; easing.type: Easing.InOutSine }
                                }
                            }

                            // Inner circle
                            Rectangle {
                                anchors.centerIn: parent
                                width: rootObj.s(76)
                                height: rootObj.s(76)
                                radius: width / 2
                                color: Qt.alpha(parent.parent.activeColor, 0.22)
                                border.width: 1.5
                                border.color: parent.parent.activeColor

                                Text {
                                    anchors.centerIn: parent
                                    text: fingerprintTabRoot.enrollStatus === "completed" ? "󰄬" : "󰈷"
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: rootObj.s(36)
                                    color: parent.parent.parent.activeColor

                                    Behavior on color {
                                        ColorAnimation { duration: 200 }
                                    }
                                }
                            }
                        }

                        // Progress Bar & Percentage
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)

                            // Instruction Message
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: fingerprintTabRoot.enrollMessage
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(13)
                                font.bold: true
                                color: parent.parent.activeColor
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Progress Track
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: true
                                Layout.maximumWidth: rootObj.s(380)
                                implicitHeight: rootObj.s(8)
                                radius: rootObj.s(4)
                                color: ThemeBackend.surface1
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * (Math.max(0, Math.min(100, fingerprintTabRoot.currentPercent)) / 100.0)
                                    radius: rootObj.s(4)
                                    color: parent.parent.parent.activeColor

                                    Behavior on width {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 250 }
                                    }
                                }
                            }
                        }

                        // Action Controls (Cancel / Done / Retry)
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: rootObj.s(10)

                            ClickButton {
                                visible: fingerprintTabRoot.enrollStatus === "failed"
                                implicitHeight: rootObj.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonText: I18n.t("guide.fingerprint.enroll.button_retry", "Попробовать снова")
                                buttonIcon: "󰑐"
                                accentColor: ThemeBackend.mauve
                                textColor: ThemeBackend.crust
                                onClicked: fingerprintTabRoot.startEnrollment()
                            }

                            ClickButton {
                                visible: fingerprintTabRoot.enrollStatus === "completed"
                                implicitHeight: rootObj.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonText: I18n.t("guide.fingerprint.enroll.button_done", "Готово")
                                buttonIcon: "󰄬"
                                accentColor: ThemeBackend.green
                                textColor: ThemeBackend.crust
                                onClicked: {
                                    fingerprintTabRoot.isEnrolling = false;
                                    listProcess.running = true;
                                }
                            }

                            ClickButton {
                                visible: fingerprintTabRoot.enrollStatus !== "completed"
                                implicitHeight: rootObj.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonText: I18n.t("guide.fingerprint.enroll.button_cancel", "Отмена")
                                buttonIcon: "󰜺"
                                accentColor: ThemeBackend.surface1
                                textColor: ThemeBackend.text
                                onClicked: fingerprintTabRoot.cancelEnrollment()
                            }
                        }
                    }
                }
            }

            // 4. Enrolled Fingerprints List Section
            SettingsGroup {
                visible: fingerprintTabRoot.hardwareAvailable
                rootObj: fingerprintTabRoot.rootObj
                icon: "󰈷"
                title: I18n.t("guide.fingerprint.enrolled.title", "Сохранённые отпечатки")
                description: I18n.t("guide.fingerprint.enrolled.desc", "Список пальцев, зарегистрированных в системе")
                expanded: true

                // Delete All button in header if more than 1 finger is enrolled
                ClickButton {
                    visible: fingerprintTabRoot.enrolledFingers.length > 1
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    implicitHeight: rootObj.s(28)
                    horizontalPadding: rootObj.s(10)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonText: I18n.t("guide.fingerprint.enrolled.delete_all", "Удалить все")
                    buttonIcon: "󰆴"
                    iconFontSize: rootObj.s(13)
                    textFontSize: rootObj.s(11)
                    accentColor: Qt.alpha(ThemeBackend.red, 0.15)
                    textColor: ThemeBackend.red
                    onClicked: fingerprintTabRoot.deleteAllFingers()
                }

                subSettings: [
                    // Empty state banner
                    Rectangle {
                        visible: fingerprintTabRoot.enrolledFingers.length === 0
                        Layout.fillWidth: true
                        implicitHeight: emptyCol.implicitHeight + rootObj.s(24)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.surface1, 0.25)

                        ColumnLayout {
                            id: emptyCol
                            anchors.centerIn: parent
                            spacing: rootObj.s(6)

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "󰈷"
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: rootObj.s(28)
                                color: ThemeBackend.surface2
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: I18n.t("guide.fingerprint.enrolled.empty_title", "Нет сохранённых отпечатков")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(13)
                                font.bold: true
                                color: ThemeBackend.text
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: I18n.t("guide.fingerprint.enrolled.empty_desc", "Зарегистрируйте палец выше, чтобы входить в систему без ввода пароля")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                color: ThemeBackend.subtext0
                            }
                        }
                    },

                    // List of enrolled fingers
                    Repeater {
                        model: fingerprintTabRoot.enrolledFingers

                        delegate: SettingsRow {
                            rootObj: fingerprintTabRoot.rootObj
                            baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                            icon: "󰈷"
                            iconAccentColor: ThemeBackend.mauve
                            iconTextColor: ThemeBackend.crust
                            title: fingerprintTabRoot.getFingerLabel(modelData)
                            description: I18n.t("guide.fingerprint.enrolled.item_desc", "Биометрическая разблокировка активна")

                            IconButton {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                size: rootObj.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: "󰆴"
                                iconFontSize: rootObj.s(15)
                                accentColor: Qt.alpha(ThemeBackend.red, 0.15)
                                textColor: ThemeBackend.red
                                onClicked: fingerprintTabRoot.deleteFinger(modelData)
                            }
                        }
                    }
                ]
            }

            // 5. Attempt Limits Group
            SettingsGroup {
                visible: fingerprintTabRoot.hardwareAvailable
                rootObj: fingerprintTabRoot.rootObj
                icon: "󰦝"
                title: I18n.t("guide.fingerprint.limits.title", "Ограничение попыток")
                description: I18n.t("guide.fingerprint.limits.desc", "Временная блокировка сканера после серии неудачных попыток")
                expanded: fingerprintTabRoot.currentAttemptLimitEnabled

                Toggle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    checked: fingerprintTabRoot.currentAttemptLimitEnabled
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface1
                    handleColor: ThemeBackend.crust
                    handleOffColor: ThemeBackend.text
                    onToggled: function(c) {
                        fingerprintTabRoot.currentAttemptLimitEnabled = c;
                        fingerprintTabRoot.updateLockscreenSetting("attemptLimitEnabled", c);
                    }
                }

                subSettings: [
                    SettingsRow {
                        rootObj: fingerprintTabRoot.rootObj
                        baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                        icon: "󰈷"
                        title: I18n.t("guide.fingerprint.limits.attempts_title", "Максимум попыток для отпечатка")
                        description: I18n.t("guide.fingerprint.limits.attempts_desc", "Число неудачных сканирований перед отключением датчика до разблокировки паролем")

                        NumberSelector {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: rootObj.s(120)
                            implicitHeight: rootObj.s(32)
                            from: 1
                            to: 20
                            stepSize: 1
                            decimals: 0
                            value: fingerprintTabRoot.currentFingerprintMaxAttempts
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
                                if (!isNaN(v) && v > 0 && fingerprintTabRoot.currentFingerprintMaxAttempts !== v) {
                                    fingerprintTabRoot.currentFingerprintMaxAttempts = v;
                                    fingerprintTabRoot.updateLockscreenSetting("fingerprintMaxAttempts", v);
                                }
                            }
                        }
                    }
                ]
            }
        }
    }
}

