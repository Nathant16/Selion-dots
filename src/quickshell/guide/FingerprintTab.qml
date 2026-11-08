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
    property int enrollStages: 9
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

    // Active enrollment process and modal state
    property bool showEnrollModal: false
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

    function openEnrollModal() {
        if (availableFingers.length === 0) return;
        selectedFingerName = availableFingers[0];
        currentStage = 0;
        currentPercent = 0;
        enrollStatus = "ready";
        enrollMessage = I18n.t("guide.fingerprint.enroll.place_finger", "Place your finger on the sensor");
        iconPulseScale = 1.0;
        iconShakeX = 0.0;
        iconCurrentColor = ThemeBackend.mauve;
        showEnrollModal = true;
    }

    function closeEnrollModal() {
        if (isEnrolling) {
            cancelEnrollment();
        }
        showEnrollModal = false;
        autoCloseTimer.stop();
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
        showEnrollModal = true;
        enrollProcess.command = ["bash", fingerprintTabRoot.scriptPath, "enroll", selectedFingerName];
        enrollProcess.running = true;
    }

    function cancelEnrollment() {
        if (enrollProcess.running) {
            enrollProcess.running = false;
        }
        isEnrolling = false;
        enrollStatus = "ready";
        showEnrollModal = false;
        autoCloseTimer.stop();
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
            fingerprintTabRoot.closeEnrollModal();
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
            if (modalFingerDropdown && modalFingerDropdown.isOpen) modalFingerDropdown.closePopup();
            if (fingerprintTabRoot.isEnrolling) {
                cancelEnrollment();
            } else {
                showEnrollModal = false;
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

            // 1. Master Authentication Toggle
            SettingsBlob {
                SettingsRow {
                    settingId: "fingerprint_master"
                    searchKeywords: "fingerprint biometrics unlock enable fprintd auth"
                    rootObj: fingerprintTabRoot.rootObj
                    icon: "󰈷"
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

            // 2. Hardware Status Section (Hidden if master switch is OFF, like in Dock)
            SettingsBlob {
                visible: fingerprintTabRoot.currentFingerprintEnabled

                SettingsRow {
                    settingId: "fingerprint_hardware"
                    searchKeywords: "fingerprint scanner sensor reader device hardware"
                    rootObj: fingerprintTabRoot.rootObj
                    icon: fingerprintTabRoot.hardwareAvailable ? "󰍹" : "󱏙"
                    title: fingerprintTabRoot.hardwareAvailable
                        ? (fingerprintTabRoot.deviceName || I18n.t("guide.fingerprint.header.title", "Fingerprint Reader"))
                        : I18n.t("guide.fingerprint.header.not_found", "No scanner detected")
                    description: fingerprintTabRoot.hardwareAvailable
                        ? (fingerprintTabRoot.enrolledFingers.length + " " + I18n.t("guide.fingerprint.enrolled_count", "fingerprints registered") + " • " + (fingerprintTabRoot.scanType === "swipe" ? I18n.t("guide.fingerprint.header.swipe_type", "Swipe") : I18n.t("guide.fingerprint.header.touch_type", "Touch")))
                        : I18n.t("guide.fingerprint.header.not_found_desc", "Biometric reader not found on this system")
                }
            }

            // 3. Registered Fingerprints Objects Section (Structured like Idle timeout objects)
            SettingsBlob {
                visible: fingerprintTabRoot.currentFingerprintEnabled && fingerprintTabRoot.hardwareAvailable

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: rootObj.s(10)

                    // Section Header with + icon button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(10)

                        Item {
                            implicitWidth: rootObj.s(32)
                            implicitHeight: rootObj.s(32)
                            Rectangle {
                                anchors.fill: parent
                                radius: rootObj.s(8)
                                color: ThemeBackend.surface0
                                Text {
                                   anchors.centerIn: parent
                                   text: "󰈷"
                                   font.family: ThemeBackend.fontFamily
                                   font.pixelSize: rootObj.s(16)
                                   color: ThemeBackend.mauve
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)

                            Text {
                                Layout.fillWidth: true
                                text: I18n.t("guide.fingerprint.objects_header.title", "Registered Fingerprints")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(14)
                                font.weight: Font.DemiBold
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
                            cornerRadius: rootObj.s(8)
                            buttonIcon: "󰐕"
                            iconFontSize: rootObj.s(14)
                            accentColor: ThemeBackend.surface0
                            textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
                            enabled: !fingerprintTabRoot.isEnrolling && fingerprintTabRoot.availableFingers.length > 0
                            onClicked: {
                                fingerprintTabRoot.openEnrollModal();
                            }
                        }
                    }

                    // List of Enrolled Fingerprints
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(6)

                        SettingsRow {
                            visible: fingerprintTabRoot.enrolledFingers.length === 0
                            settingId: "fingerprint_none"
                            searchKeywords: "fingerprint empty no fingerprints enrolled"
                            rootObj: fingerprintTabRoot.rootObj
                            icon: "󰋗"
                            title: I18n.t("guide.fingerprint.enrolled.empty_title", "No fingerprints saved")
                            description: I18n.t("guide.fingerprint.enrolled.empty_desc", "Click + to register a finger for quick login and unlocking")
                        }

                        Repeater {
                            model: fingerprintTabRoot.enrolledFingers
                            delegate: SettingsRow {
                                required property var modelData
                                settingId: "fingerprint_finger_" + modelData
                                searchKeywords: "fingerprint " + modelData
                                rootObj: fingerprintTabRoot.rootObj
                                icon: "󰈷"
                                title: fingerprintTabRoot.getFingerLabel(modelData)
                                description: I18n.t("guide.fingerprint.finger_registered", "Registered on %1").arg(fingerprintTabRoot.deviceName || "Synaptics Sensors")

                                DeleteButton {
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    size: rootObj.s(28)
                                    cornerRadius: Math.min(ThemeBackend.borderRadius, rootObj.s(8))
                                    iconFontSize: rootObj.s(14)
                                    onClicked: fingerprintTabRoot.deleteFinger(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Modal Floating Banner for Fingerprint Enrollment (Cannot be dismissed while scanning)
    Item {
        id: modalOverlay
        anchors.fill: parent
        visible: opacity > 0.001
        opacity: (fingerprintTabRoot.showEnrollModal || fingerprintTabRoot.isEnrolling) ? 1.0 : 0.0
        z: 100
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Semi-transparent backdrop
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(ThemeBackend.crust, 0.75)
            MouseArea {
                anchors.fill: parent
                // While enrolling, clicking outside CANNOT close the modal!
                onClicked: {
                    if (!fingerprintTabRoot.isEnrolling) {
                        fingerprintTabRoot.closeEnrollModal();
                    }
                }
            }
        }

        // Floating Card in the center
        Rectangle {
            id: modalCard
            anchors.centerIn: parent
            width: Math.min(parent.width - rootObj.s(32), rootObj.s(380))
            implicitHeight: modalCardCol.implicitHeight + rootObj.s(36)
            radius: Math.min(rootObj.s(18), ThemeBackend.borderRadius * 1.5)
            color: ThemeBackend.mantle
            border.color: Qt.alpha(ThemeBackend.surface1, 0.8)
            border.width: 1
            clip: true

            MouseArea {
                anchors.fill: parent
                // Absorb clicks so they don't penetrate
            }

            ColumnLayout {
                id: modalCardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: rootObj.s(18)
                spacing: rootObj.s(14)

                // Modal Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: rootObj.s(8)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)

                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("guide.fingerprint.modal.title", "Enroll Fingerprint")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(16)
                            font.weight: Font.Bold
                            color: ThemeBackend.text
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: fingerprintTabRoot.isEnrolling
                                ? fingerprintTabRoot.getFingerLabel(fingerprintTabRoot.selectedFingerName)
                                : I18n.t("guide.fingerprint.modal.select_desc", "Select a finger to register")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                            elide: Text.ElideRight
                        }
                    }

                    CloseButton {
                        visible: !fingerprintTabRoot.isEnrolling
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        size: rootObj.s(28)
                        cornerRadius: rootObj.s(8)
                        onClicked: fingerprintTabRoot.closeEnrollModal()
                    }
                }

                // Central Fingerprint Icon with reactive touch animations
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: rootObj.s(110)
                    implicitHeight: rootObj.s(110)

                    // Background pulsing glow ring
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * fingerprintTabRoot.iconPulseScale
                        height: parent.height * fingerprintTabRoot.iconPulseScale
                        radius: width / 2
                        color: Qt.alpha(fingerprintTabRoot.iconCurrentColor, 0.12)
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }

                    // Inner circle
                    Rectangle {
                        anchors.centerIn: parent
                        width: rootObj.s(86)
                        height: rootObj.s(86)
                        radius: width / 2
                        color: ThemeBackend.surface0
                        border.color: Qt.alpha(fingerprintTabRoot.iconCurrentColor, 0.5)
                        border.width: 2
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        Text {
                            anchors.centerIn: parent
                            text: fingerprintTabRoot.enrollStatus === "completed" ? "󰄲" : "󰈷"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(44)
                            scale: fingerprintTabRoot.iconPulseScale
                            color: fingerprintTabRoot.iconCurrentColor
                            transform: Translate { x: fingerprintTabRoot.iconShakeX }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                }

                // Instruction message
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: rootObj.s(8)
                    Layout.rightMargin: rootObj.s(8)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: fingerprintTabRoot.enrollMessage
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(13)
                    font.weight: Font.Medium
                    color: fingerprintTabRoot.iconCurrentColor === ThemeBackend.peach
                        ? ThemeBackend.peach
                        : (fingerprintTabRoot.enrollStatus === "completed" ? ThemeBackend.green : ThemeBackend.text)
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // Progress Bar & Stage Indicator (Visible when enrolling or completed)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: fingerprintTabRoot.isEnrolling || fingerprintTabRoot.enrollStatus === "completed"
                    spacing: rootObj.s(6)

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.t("guide.fingerprint.modal.stage_info", "Stage %1 of %2 (%3%)")
                            .arg(fingerprintTabRoot.currentStage)
                            .arg(fingerprintTabRoot.enrollStages)
                            .arg(fingerprintTabRoot.currentPercent)
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.subtext0
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rootObj.s(6)
                        radius: rootObj.s(3)
                        color: ThemeBackend.surface0
                        clip: true

                        Rectangle {
                            height: parent.height
                            width: parent.width * (fingerprintTabRoot.currentPercent / 100.0)
                            radius: rootObj.s(3)
                            color: fingerprintTabRoot.enrollStatus === "completed" ? ThemeBackend.green : ThemeBackend.mauve
                            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                }

                // Selection phase controls (when NOT enrolling yet)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !fingerprintTabRoot.isEnrolling && fingerprintTabRoot.enrollStatus !== "completed"
                    spacing: rootObj.s(12)

                    Dropdown {
                        id: modalFingerDropdown
                        Layout.fillWidth: true
                        implicitHeight: rootObj.s(34)
                        options: {
                            let opts = [];
                            for (let i = 0; i < fingerprintTabRoot.availableFingers.length; i++) {
                                opts.push(fingerprintTabRoot.getFingerLabel(fingerprintTabRoot.availableFingers[i]));
                            }
                            return opts;
                        }
                        currentIndex: 0
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface0
                        hoverColor: ThemeBackend.surface1
                        dropdownColor: ThemeBackend.surface0
                        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                        textColor: ThemeBackend.text
                        activeTextColor: ThemeBackend.crust
                        fontPixelSize: rootObj.s(12)
                        onValueChanged: function(index, value) {
                            if (index >= 0 && index < fingerprintTabRoot.availableFingers.length) {
                                fingerprintTabRoot.selectedFingerName = fingerprintTabRoot.availableFingers[index];
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(8)

                        ClickButton {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(34)
                            buttonText: I18n.t("guide.fingerprint.modal.cancel", "Cancel")
                            accentColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text
                            cornerRadius: ThemeBackend.borderRadius
                            onTriggered: fingerprintTabRoot.closeEnrollModal()
                        }

                        ClickButton {
                            Layout.fillWidth: true
                            implicitHeight: rootObj.s(34)
                            buttonText: I18n.t("guide.fingerprint.modal.start", "Start Scan")
                            buttonIcon: "󰐕"
                            accentColor: ThemeBackend.mauve
                            textColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius
                            enabled: fingerprintTabRoot.availableFingers.length > 0
                            onTriggered: fingerprintTabRoot.startEnrollment()
                        }
                    }
                }

                // Active scanning / Finished controls
                RowLayout {
                    Layout.fillWidth: true
                    visible: fingerprintTabRoot.isEnrolling || fingerprintTabRoot.enrollStatus === "completed"
                    spacing: rootObj.s(8)

                    ClickButton {
                        Layout.fillWidth: true
                        implicitHeight: rootObj.s(34)
                        buttonText: fingerprintTabRoot.enrollStatus === "completed"
                            ? I18n.t("guide.fingerprint.modal.done", "Done")
                            : I18n.t("guide.fingerprint.modal.cancel", "Cancel")
                        buttonIcon: fingerprintTabRoot.enrollStatus === "completed" ? "󰄲" : "󰜺"
                        accentColor: fingerprintTabRoot.enrollStatus === "completed" ? ThemeBackend.green : ThemeBackend.surface0
                        textColor: fingerprintTabRoot.enrollStatus === "completed" ? ThemeBackend.crust : ThemeBackend.text
                        cornerRadius: ThemeBackend.borderRadius
                        onTriggered: {
                            if (fingerprintTabRoot.enrollStatus === "completed") {
                                fingerprintTabRoot.closeEnrollModal();
                            } else {
                                fingerprintTabRoot.cancelEnrollment();
                            }
                        }
                    }
                }
            }
        }
    }
}
