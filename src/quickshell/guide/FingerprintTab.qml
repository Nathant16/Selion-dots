import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/buttons"
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

    // Hardware and backend state
    property bool hardwareAvailable: false
    property string deviceName: ""
    property string scanType: "press"
    property int enrollStages: 10
    property var enrolledFingers: []

    readonly property var allFingers: [
        "right-index-finger",
        "right-thumb",
        "right-middle-finger",
        "right-ring-finger",
        "right-little-finger",
        "left-index-finger",
        "left-thumb",
        "left-middle-finger",
        "left-ring-finger",
        "left-little-finger"
    ]

    readonly property var availableFingers: {
        let list = [];
        for (let i = 0; i < allFingers.length; i++) {
            let f = allFingers[i];
            if (enrolledFingers.indexOf(f) === -1) {
                list.push(f);
            }
        }
        return list;
    }

    // Enrollment selection state
    property string selectedFingerName: availableFingers.length > 0 ? availableFingers[0] : "right-index-finger"

    // Active enrollment process state
    property bool isEnrolling: false
    property int currentStage: 0
    property int currentPercent: 0
    property string enrollStatus: "ready"
    property string enrollMessage: ""

    // Animated reaction properties for the fingerprint icon in modal
    property real iconPulseScale: 1.0
    property real iconShakeX: 0.0
    property color iconCurrentColor: ThemeBackend.mauve

    readonly property string scriptPath: (typeof Caching !== "undefined" && Caching.serpantinumDir)
        ? (Caching.serpantinumDir + "/scripts/system/fingerprint_manager.sh")
        : "fingerprint_manager.sh"

    function syncSettings() {
        let s = (typeof Config !== "undefined" && typeof Config.getSetting === "function")
            ? Config.getSetting("lockscreen", fingerprintTabRoot.defaultLockscreenSettings)
            : fingerprintTabRoot.defaultLockscreenSettings;
        fingerprintTabRoot.lockscreenSettings = s;
        fingerprintTabRoot.currentFingerprintEnabled = s.fingerprintEnabled !== false;
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

    function startEnrollment() {
        currentStage = 0;
        currentPercent = 0;
        enrollStatus = "ready";
        enrollMessage = I18n.t("guide.fingerprint.enroll.place_finger", "Place your finger on the sensor");
        iconPulseScale = 1.0;
        iconShakeX = 0.0;
        iconCurrentColor = ThemeBackend.mauve;
        isEnrolling = true;
        enrollProcess.command = ["bash", fingerprintTabRoot.scriptPath, "enroll", selectedFingerName];
        enrollProcess.running = true;
    }

    function cancelEnrollment() {
        if (enrollProcess.running) {
            enrollProcess.running = false;
        }
        isEnrolling = false;
        enrollStatus = "ready";
        autoCloseTimer.stop();
        enrollPopup.close();
    }

    function deleteFinger(finger) {
        deleteProcess.command = ["bash", fingerprintTabRoot.scriptPath, "delete", finger];
        deleteProcess.running = true;
    }

    // Touch reaction animations
    SequentialAnimation {
        id: pulseAnim
        running: false
        NumberAnimation { target: fingerprintTabRoot; property: "iconPulseScale"; to: 1.32; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: fingerprintTabRoot; property: "iconPulseScale"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
    }

    SequentialAnimation {
        id: shakeAnim
        running: false
        NumberAnimation { target: fingerprintTabRoot; property: "iconShakeX"; to: -10; duration: 45 }
        NumberAnimation { target: fingerprintTabRoot; property: "iconShakeX"; to: 10; duration: 55 }
        NumberAnimation { target: fingerprintTabRoot; property: "iconShakeX"; to: -8; duration: 55 }
        NumberAnimation { target: fingerprintTabRoot; property: "iconShakeX"; to: 8; duration: 55 }
        NumberAnimation { target: fingerprintTabRoot; property: "iconShakeX"; to: 0; duration: 60 }
    }

    Timer {
        id: colorResetTimer
        interval: 650
        repeat: false
        onTriggered: {
            if (fingerprintTabRoot.enrollStatus !== "completed") {
                fingerprintTabRoot.iconCurrentColor = ThemeBackend.mauve;
            }
        }
    }

    Timer {
        id: autoCloseTimer
        interval: 1500
        repeat: false
        onTriggered: {
            enrollPopup.close();
        }
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
                    if (data.stages) fingerprintTabRoot.enrollStages = Number(data.stages) || 10;
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
                    if (msg.type === "started" || msg.type === "ready") {
                        fingerprintTabRoot.currentStage = 0;
                        fingerprintTabRoot.currentPercent = 0;
                        fingerprintTabRoot.enrollStatus = "ready";
                        fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.place_finger", "Place your finger on the sensor");
                        fingerprintTabRoot.iconCurrentColor = ThemeBackend.mauve;
                    } else if (msg.type === "progress") {
                        fingerprintTabRoot.currentStage = msg.stage || 0;
                        fingerprintTabRoot.currentPercent = msg.percent || 0;
                        fingerprintTabRoot.enrollStatus = msg.status || "stage_passed";
                        if (msg.status === "stage_passed") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.step_passed", "Lift finger and place it again");
                            fingerprintTabRoot.iconCurrentColor = ThemeBackend.green;
                            pulseAnim.restart();
                            colorResetTimer.restart();
                        } else if (msg.status === "retry_scan") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.retry", "Could not read. Try again");
                            fingerprintTabRoot.iconCurrentColor = ThemeBackend.peach;
                            shakeAnim.restart();
                            colorResetTimer.restart();
                        } else if (msg.status === "swipe_too_short") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.swipe_too_short", "Swipe too short. Try again slower");
                            fingerprintTabRoot.iconCurrentColor = ThemeBackend.peach;
                            shakeAnim.restart();
                            colorResetTimer.restart();
                        } else if (msg.status === "not_centered") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.not_centered", "Center your finger on the sensor");
                            fingerprintTabRoot.iconCurrentColor = ThemeBackend.peach;
                            shakeAnim.restart();
                            colorResetTimer.restart();
                        } else if (msg.status === "remove_retry") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.remove_retry", "Remove your finger and place it again");
                            fingerprintTabRoot.iconCurrentColor = ThemeBackend.peach;
                            shakeAnim.restart();
                            colorResetTimer.restart();
                        } else if (msg.message) {
                            fingerprintTabRoot.enrollMessage = msg.message;
                        }
                    } else if (msg.type === "completed") {
                        fingerprintTabRoot.currentStage = fingerprintTabRoot.enrollStages;
                        fingerprintTabRoot.currentPercent = 100;
                        fingerprintTabRoot.enrollStatus = "completed";
                        fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.success", "Fingerprint enrolled successfully!");
                        fingerprintTabRoot.iconCurrentColor = ThemeBackend.green;
                        pulseAnim.restart();
                        listProcess.running = true;
                        autoCloseTimer.restart();
                    } else if (msg.type === "failed") {
                        fingerprintTabRoot.enrollStatus = "failed";
                        fingerprintTabRoot.enrollMessage = msg.message || I18n.t("guide.fingerprint.enroll.failed", "Failed to enroll fingerprint");
                        fingerprintTabRoot.iconCurrentColor = ThemeBackend.red;
                        shakeAnim.restart();
                    } else if (msg.type === "finished") {
                        if (msg.success) {
                            listProcess.running = true;
                        }
                    }
                } catch(e) {}
            }
        }
        onExited: {
            fingerprintTabRoot.isEnrolling = false;
        }
    }

    // Auto-refresh timer so fingerprints update automatically
    Timer {
        interval: 5000
        repeat: true
        running: fingerprintTabRoot.visible && !fingerprintTabRoot.isEnrolling
        onTriggered: {
            if (!listProcess.running) listProcess.running = true;
        }
    }

    onVisibleChanged: {
        if (visible) {
            syncSettings();
            refreshHardware();
        } else {
            enrollPopup.close();
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

    Component {
        id: fingerCardDelegate
        SettingsRow {
            id: fingerCard
            required property var modelData
            required property int index

            rootObj: fingerprintTabRoot.rootObj
            Layout.fillWidth: true

            settingId: "fingerprint_finger_" + modelData
            searchKeywords: "fingerprint " + modelData
            title: fingerprintTabRoot.getFingerLabel(modelData)
            showIcon: false

            baseColor: ThemeBackend.glassActive
                ? Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity * 0.6)
                : Qt.alpha(ThemeBackend.surface0, 0.4)
            borderColor: Qt.alpha(ThemeBackend.surface1, 0.4)
            borderWidth: 1
            horizontalPadding: rootObj.s(12)
            verticalPadding: rootObj.s(10)
            spacing: rootObj.s(12)
            innerSpacing: 0
            bottomSpacing: 0

            DeleteButton {
                Layout.alignment: Qt.AlignVCenter
                size: rootObj.s(28)
                cornerRadius: rootObj.s(8)
                iconFontSize: rootObj.s(14)
                onClicked: {
                    fingerprintTabRoot.deleteFinger(fingerCard.modelData);
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(8)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(8)
        contentHeight: settingsCol.implicitHeight
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
            width: parent.width
            spacing: rootObj.s(6)

            // 1. Master Authentication Toggle
            SettingsBlob {
                SettingsRow {
                    settingId: "fingerprint_master"
                    searchKeywords: "fingerprint biometrics unlock enable fprintd auth"
                    rootObj: fingerprintTabRoot.rootObj
                    icon: "󰌾"
                    title: I18n.t("guide.fingerprint.master.title", "Fingerprint authentication")
                    description: I18n.t("guide.fingerprint.master.desc", "Allow unlocking the screen and authenticating with fingerprint")

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: fingerprintTabRoot.currentFingerprintEnabled
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(val) {
                            fingerprintTabRoot.currentFingerprintEnabled = val;
                            fingerprintTabRoot.updateLockscreenSetting("fingerprintEnabled", val);
                        }
                    }
                }
            }

            // 2. Registered Fingerprints Objects Section (Matches Idle Timeout Objects composition)
            CollapsibleSection {
                open: fingerprintTabRoot.currentFingerprintEnabled
                row: objectsCard

                Rectangle {
                    id: objectsCard
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: objectsBoxCol.implicitHeight + rootObj.s(24)
                    radius: ThemeBackend.borderRadius
                    color: gf1.active
                        ? "transparent"
                        : (ThemeBackend.glassActive
                            ? Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity * 0.7)
                            : Qt.alpha(ThemeBackend.surface0, 0.4))
                    clip: true

                    GlassFill {
                        id: gf1
                        anchors.fill: parent
                        radius: parent.radius
                        tintColor: Qt.alpha(ThemeBackend.surface0, 0.4)
                        tintAmount: 0.25
                    }

                    ColumnLayout {
                        id: objectsBoxCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: rootObj.s(12)
                        spacing: rootObj.s(10)

                        // Section Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(12)

                            IconButton {
                                enabled: false
                                size: rootObj.s(32)
                                Layout.preferredWidth: rootObj.s(32)
                                Layout.preferredHeight: rootObj.s(32)
                                Layout.alignment: Qt.AlignVCenter
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: "󰈷"
                                iconFontSize: rootObj.s(16)
                                accentColor: ThemeBackend.surface0
                                textColor: "#ffffff"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.alignment: Qt.AlignVCenter
                                spacing: rootObj.s(2)

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.t("guide.fingerprint.objects_header.title", "Registered Fingerprints")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(14)
                                    color: ThemeBackend.text
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.t("guide.fingerprint.objects_header.desc", "Manage enrolled fingerprints and add new fingers")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                    color: ThemeBackend.subtext0
                                    elide: Text.ElideRight
                                }
                            }

                            IconButton {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                size: rootObj.s(32)
                                Layout.preferredWidth: rootObj.s(32)
                                Layout.preferredHeight: rootObj.s(32)
                                cornerRadius: rootObj.s(8)
                                buttonIcon: "󰐕"
                                iconFontSize: rootObj.s(14)
                                accentColor: ThemeBackend.surface0
                                textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
                                enabled: !fingerprintTabRoot.isEnrolling && fingerprintTabRoot.availableFingers.length > 0
                                onClicked: {
                                    enrollPopup.openPopup();
                                }
                            }
                        }

                        // List of Fingerprint Cards (Only visible when fingerprints exist)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(8)
                            visible: fingerprintTabRoot.enrolledFingers.length > 0

                            Repeater {
                                model: fingerprintTabRoot.enrolledFingers
                                delegate: fingerCardDelegate
                            }
                        }
                    }
                }
            }
        }
    }

    FingerprintEnrollPopup {
        id: enrollPopup
        tab: fingerprintTabRoot
        rootObj: fingerprintTabRoot.rootObj
    }
}
