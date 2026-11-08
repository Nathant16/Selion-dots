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
    property string selectedFingerName: "right-index-finger"
    readonly property bool isTargetEnrolled: enrolledFingers.indexOf(selectedFingerName) !== -1

    // Active enrollment process state
    property bool isEnrolling: false
    property int currentStage: 0
    property int currentPercent: 0
    property string enrollStatus: "ready"
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

    function startEnrollment() {
        if (isTargetEnrolled) return;
        currentStage = 0;
        currentPercent = 0;
        enrollStatus = "ready";
        enrollMessage = I18n.t("guide.fingerprint.enroll.place_finger", "Place your finger on the sensor");
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
    }

    function deleteFinger(finger) {
        deleteProcess.command = ["bash", fingerprintTabRoot.scriptPath, "delete", finger];
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
                        fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.place_finger", "Place your finger on the sensor");
                    } else if (msg.type === "progress") {
                        fingerprintTabRoot.currentStage = msg.stage || 0;
                        fingerprintTabRoot.currentPercent = msg.percent || 0;
                        fingerprintTabRoot.enrollStatus = msg.status || "stage_passed";
                        if (msg.status === "stage_passed") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.step_passed", "Lift finger and place it again");
                        } else if (msg.status === "retry_scan") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.retry", "Could not read. Try again");
                        } else if (msg.status === "swipe_too_short") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.swipe_too_short", "Swipe too short. Try again slower");
                        } else if (msg.status === "not_centered") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.not_centered", "Center your finger on the sensor");
                        } else if (msg.status === "remove_retry") {
                            fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.remove_retry", "Remove your finger and place it again");
                        } else if (msg.message) {
                            fingerprintTabRoot.enrollMessage = msg.message;
                        }
                    } else if (msg.type === "completed") {
                        fingerprintTabRoot.currentStage = fingerprintTabRoot.enrollStages;
                        fingerprintTabRoot.currentPercent = 100;
                        fingerprintTabRoot.enrollStatus = "completed";
                        fingerprintTabRoot.enrollMessage = I18n.t("guide.fingerprint.enroll.success", "Fingerprint enrolled successfully!");
                        listProcess.running = true;
                    } else if (msg.type === "failed") {
                        fingerprintTabRoot.enrollStatus = "failed";
                        fingerprintTabRoot.enrollMessage = msg.message || I18n.t("guide.fingerprint.enroll.failed", "Failed to enroll fingerprint");
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

    onVisibleChanged: {
        if (visible) {
            syncSettings();
            refreshHardware();
        } else {
            if (fingerDropdown && fingerDropdown.isOpen) fingerDropdown.closePopup();
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

            // 1. Authentication Options
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

                SettingsRow {
                    settingId: "fingerprint_limits"
                    searchKeywords: "fingerprint failed attempts limit lock lockout"
                    rootObj: fingerprintTabRoot.rootObj
                    icon: "󰌾"
                    title: I18n.t("guide.fingerprint.limits.title", "Limit failed attempts")
                    description: I18n.t("guide.fingerprint.limits.desc", "Temporarily disable sensor after 5 consecutive failed attempts")

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: fingerprintTabRoot.currentAttemptLimitEnabled
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(val) {
                            fingerprintTabRoot.currentAttemptLimitEnabled = val;
                            fingerprintTabRoot.updateLockscreenSetting("attemptLimitEnabled", val);
                        }
                    }
                }
            }

            // 2. Hardware Status Section
            SettingsBlob {
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

                    ClickButton {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitHeight: rootObj.s(32)
                        buttonText: I18n.t("guide.fingerprint.refresh", "Refresh")
                        buttonIcon: "󰑐"
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.crust
                        cornerRadius: ThemeBackend.borderRadius
                        horizontalPadding: rootObj.s(14)
                        iconFontSize: rootObj.s(14)
                        textFontSize: rootObj.s(11)
                        onTriggered: fingerprintTabRoot.refreshHardware()
                    }
                }
            }

            // 3. Enrolled Fingerprints
            SettingsBlob {
                visible: fingerprintTabRoot.hardwareAvailable

                SettingsRow {
                    visible: fingerprintTabRoot.enrolledFingers.length === 0
                    settingId: "fingerprint_none"
                    searchKeywords: "fingerprint empty no fingerprints enrolled"
                    rootObj: fingerprintTabRoot.rootObj
                    icon: "󰋗"
                    title: I18n.t("guide.fingerprint.enrolled.empty_title", "No fingerprints saved")
                    description: I18n.t("guide.fingerprint.enrolled.empty_desc", "Enroll a finger below to log in and unlock without typing your password")
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
                        description: modelData

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

            // 4. Enroll Fingerprint Section
            SettingsBlob {
                visible: fingerprintTabRoot.hardwareAvailable

                SettingsRow {
                    settingId: "fingerprint_enroll"
                    searchKeywords: "fingerprint add enroll new finger scan"
                    rootObj: fingerprintTabRoot.rootObj
                    icon: "󰐕"
                    title: fingerprintTabRoot.isEnrolling
                        ? (I18n.t("guide.fingerprint.enroll.title", "Add fingerprint") + " (" + fingerprintTabRoot.currentPercent + "%)")
                        : I18n.t("guide.fingerprint.enroll.title", "Add fingerprint")
                    description: {
                        if (fingerprintTabRoot.isEnrolling) {
                            return fingerprintTabRoot.enrollMessage;
                        }
                        if (fingerprintTabRoot.isTargetEnrolled) {
                            return I18n.t("guide.fingerprint.enroll.already_enrolled", "Already enrolled");
                        }
                        return I18n.t("guide.fingerprint.enroll.desc", "Select a finger and scan it on the sensor");
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        spacing: rootObj.s(8)

                        Dropdown {
                            id: fingerDropdown
                            enabled: !fingerprintTabRoot.isEnrolling
                            implicitWidth: rootObj.s(180)
                            implicitHeight: rootObj.s(32)
                            options: [
                                I18n.t("guide.fingerprint.fingers.right-index-finger", "Right index finger"),
                                I18n.t("guide.fingerprint.fingers.right-thumb", "Right thumb"),
                                I18n.t("guide.fingerprint.fingers.right-middle-finger", "Right middle finger"),
                                I18n.t("guide.fingerprint.fingers.right-ring-finger", "Right ring finger"),
                                I18n.t("guide.fingerprint.fingers.right-little-finger", "Right little finger"),
                                I18n.t("guide.fingerprint.fingers.left-index-finger", "Left index finger"),
                                I18n.t("guide.fingerprint.fingers.left-thumb", "Left thumb"),
                                I18n.t("guide.fingerprint.fingers.left-middle-finger", "Left middle finger"),
                                I18n.t("guide.fingerprint.fingers.left-ring-finger", "Left ring finger"),
                                I18n.t("guide.fingerprint.fingers.left-little-finger", "Left little finger")
                            ]
                            readonly property var fingerKeys: [
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
                            currentIndex: 0
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface0
                            hoverColor: ThemeBackend.surface1
                            dropdownColor: ThemeBackend.surface0
                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                            textColor: ThemeBackend.text
                            activeTextColor: ThemeBackend.crust
                            fontPixelSize: rootObj.s(11)
                            onValueChanged: function(index, value) {
                                fingerprintTabRoot.selectedFingerName = fingerKeys[index];
                            }
                        }

                        ClickButton {
                            implicitHeight: rootObj.s(32)
                            buttonText: fingerprintTabRoot.isEnrolling
                                ? I18n.t("guide.fingerprint.cancel", "Cancel")
                                : I18n.t("guide.fingerprint.enroll.button_start", "Enroll")
                            buttonIcon: fingerprintTabRoot.isEnrolling ? "󰜺" : "󰐕"
                            accentColor: fingerprintTabRoot.isEnrolling
                                ? ThemeBackend.red
                                : (fingerprintTabRoot.isTargetEnrolled ? ThemeBackend.surface2 : ThemeBackend.mauve)
                            textColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius
                            horizontalPadding: rootObj.s(14)
                            iconFontSize: rootObj.s(14)
                            textFontSize: rootObj.s(11)
                            enabled: fingerprintTabRoot.isEnrolling || (!fingerprintTabRoot.isTargetEnrolled && fingerprintTabRoot.hardwareAvailable)
                            onTriggered: {
                                if (fingerprintTabRoot.isEnrolling) {
                                    fingerprintTabRoot.cancelEnrollment();
                                } else {
                                    fingerprintTabRoot.startEnrollment();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
