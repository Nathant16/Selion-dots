import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../"
import "../reusables"
import "../reusables/buttons"
import "../reusables/inputs"

Popup {
    id: enrollPopup
    parent: rootObj ? rootObj : undefined
    x: parent && parent.width > 0 ? Math.max(0, Math.round((parent.width - width) / 2)) : 0
    y: parent && parent.height > 0 ? Math.max(0, Math.round((parent.height - height) / 2)) : 0
    modal: true
    dim: true
    width: rootObj ? Math.min(rootObj.width - rootObj.s(32), rootObj.s(420)) : 420
    padding: rootObj ? rootObj.s(20) : 20

    property var rootObj: null
    property var tab: null
    readonly property bool isEnrolling: tab ? tab.isEnrolling : false
    readonly property bool isCompleted: tab ? (tab.enrollStatus === "completed") : false
    readonly property bool canClose: !isEnrolling && !isCompleted

    closePolicy: canClose ? (Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent) : Popup.NoAutoClose

    function openPopup() {
        if (!tab || tab.availableFingers.length === 0) return;
        tab.selectedFingerName = tab.availableFingers[0];
        tab.currentStage = 0;
        tab.currentPercent = 0;
        tab.enrollStatus = "ready";
        tab.enrollMessage = I18n.t("guide.fingerprint.enroll.place_finger", "Place your finger on the sensor");
        tab.iconPulseScale = 1.0;
        tab.iconShakeX = 0.0;
        tab.iconCurrentColor = ThemeBackend.mauve;
        open();
    }

    onClosed: {
        if (modalFingerDropdown && modalFingerDropdown.isOpen) {
            modalFingerDropdown.closePopup();
        }
        if (tab && tab.isEnrolling) {
            tab.cancelEnrollment();
        }
    }

    Connections {
        target: enrollPopup.rootObj ? enrollPopup.rootObj : null
        function onVisibleChanged() {
            if (enrollPopup.rootObj && !enrollPopup.rootObj.visible) {
                enrollPopup.close();
            }
        }
    }

    background: Rectangle {
        radius: ThemeBackend.clampedBorderRadius
        color: popupGlass.active ? "transparent" : ThemeBackend.base

        GlassFill {
            id: popupGlass
            anchors.fill: parent
            radius: parent.radius
            tintColor: ThemeBackend.base
            tintAmount: 0.25
        }
    }

    contentItem: ColumnLayout {
        spacing: rootObj ? rootObj.s(14) : 14

        // Modal Header
        RowLayout {
            Layout.fillWidth: true
            spacing: rootObj ? rootObj.s(8) : 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: rootObj ? rootObj.s(2) : 2

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("guide.fingerprint.modal.title", "Enroll Fingerprint")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj ? rootObj.s(16) : 16
                    font.weight: Font.Bold
                    color: ThemeBackend.text
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: (tab && tab.isEnrolling)
                        ? tab.getFingerLabel(tab.selectedFingerName)
                        : I18n.t("guide.fingerprint.modal.select_desc", "Select a finger to register")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj ? rootObj.s(11) : 11
                    color: ThemeBackend.subtext0
                    elide: Text.ElideRight
                }
            }

            CloseButton {
                visible: enrollPopup.canClose
                size: rootObj ? rootObj.s(30) : 30
                cornerRadius: rootObj ? rootObj.s(8) : 8
                iconFontSize: rootObj ? rootObj.s(14) : 14
                onClicked: enrollPopup.close()
            }
        }

        // Central Fingerprint Icon with reactive touch animations
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: rootObj ? rootObj.s(110) : 110
            implicitHeight: rootObj ? rootObj.s(110) : 110

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * (tab ? tab.iconPulseScale : 1.0)
                height: parent.height * (tab ? tab.iconPulseScale : 1.0)
                radius: width / 2
                color: Qt.alpha(tab ? tab.iconCurrentColor : ThemeBackend.mauve, 0.12)
                Behavior on color { ColorAnimation { duration: 250 } }
            }

            Rectangle {
                anchors.centerIn: parent
                width: rootObj ? rootObj.s(86) : 86
                height: rootObj ? rootObj.s(86) : 86
                radius: width / 2
                color: ThemeBackend.surface0
                border.color: Qt.alpha(tab ? tab.iconCurrentColor : ThemeBackend.mauve, 0.5)
                border.width: 2
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: (tab && tab.enrollStatus === "completed") ? "󰄲" : "󰈷"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj ? rootObj.s(44) : 44
                    scale: tab ? tab.iconPulseScale : 1.0
                    color: tab ? tab.iconCurrentColor : ThemeBackend.mauve
                    transform: Translate { x: tab ? tab.iconShakeX : 0.0 }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        // Instruction / Status message
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: rootObj ? rootObj.s(8) : 8
            Layout.rightMargin: rootObj ? rootObj.s(8) : 8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: tab ? tab.enrollMessage : ""
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj ? rootObj.s(13) : 13
            font.weight: Font.Medium
            color: (tab && tab.iconCurrentColor === ThemeBackend.peach)
                ? ThemeBackend.peach
                : ((tab && tab.enrollStatus === "completed") ? ThemeBackend.green : ThemeBackend.text)
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // Progress bar & Stage indicator
        ColumnLayout {
            Layout.fillWidth: true
            visible: tab && (tab.isEnrolling || tab.enrollStatus === "completed")
            spacing: rootObj ? rootObj.s(6) : 6

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: I18n.t("guide.fingerprint.modal.stage_info", "Stage %1 of %2 (%3%)")
                    .arg(tab ? tab.currentStage : 0)
                    .arg(tab ? tab.enrollStages : 9)
                    .arg(tab ? tab.currentPercent : 0)
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj ? rootObj.s(11) : 11
                color: ThemeBackend.subtext0
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rootObj ? rootObj.s(6) : 6
                radius: rootObj ? rootObj.s(3) : 3
                color: ThemeBackend.surface0
                clip: true

                Rectangle {
                    height: parent.height
                    width: parent.width * ((tab ? tab.currentPercent : 0) / 100.0)
                    radius: rootObj ? rootObj.s(3) : 3
                    color: (tab && tab.enrollStatus === "completed") ? ThemeBackend.green : ThemeBackend.mauve
                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        // Finger selection controls (shown before scan starts)
        ColumnLayout {
            Layout.fillWidth: true
            visible: tab && !tab.isEnrolling && tab.enrollStatus !== "completed"
            spacing: rootObj ? rootObj.s(12) : 12

            Dropdown {
                id: modalFingerDropdown
                Layout.fillWidth: true
                implicitHeight: rootObj ? rootObj.s(34) : 34
                options: {
                    if (!tab) return [];
                    let opts = [];
                    for (let i = 0; i < tab.availableFingers.length; i++) {
                        opts.push(tab.getFingerLabel(tab.availableFingers[i]));
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
                fontPixelSize: rootObj ? rootObj.s(12) : 12
                onValueChanged: function(index, value) {
                    if (tab && index >= 0 && index < tab.availableFingers.length) {
                        tab.selectedFingerName = tab.availableFingers[index];
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: rootObj ? rootObj.s(8) : 8

                ClickButton {
                    Layout.fillWidth: true
                    implicitHeight: rootObj ? rootObj.s(34) : 34
                    buttonText: I18n.t("guide.fingerprint.modal.cancel", "Cancel")
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    cornerRadius: ThemeBackend.borderRadius
                    onTriggered: enrollPopup.close()
                }

                ClickButton {
                    Layout.fillWidth: true
                    implicitHeight: rootObj ? rootObj.s(34) : 34
                    buttonText: I18n.t("guide.fingerprint.modal.start", "Start Scan")
                    buttonIcon: "󰐕"
                    accentColor: ThemeBackend.mauve
                    textColor: ThemeBackend.crust
                    cornerRadius: ThemeBackend.borderRadius
                    enabled: tab && tab.availableFingers.length > 0
                    onTriggered: {
                        if (tab) tab.startEnrollment();
                    }
                }
            }
        }

        // Active scanning or Completed buttons
        RowLayout {
            Layout.fillWidth: true
            visible: tab && (tab.isEnrolling || tab.enrollStatus === "completed")
            spacing: rootObj ? rootObj.s(8) : 8

            ClickButton {
                Layout.fillWidth: true
                implicitHeight: rootObj ? rootObj.s(34) : 34
                buttonText: (tab && tab.enrollStatus === "completed")
                    ? I18n.t("guide.fingerprint.modal.done", "Done")
                    : I18n.t("guide.fingerprint.modal.cancel", "Cancel")
                buttonIcon: (tab && tab.enrollStatus === "completed") ? "󰄲" : "󰜺"
                accentColor: (tab && tab.enrollStatus === "completed") ? ThemeBackend.green : ThemeBackend.surface0
                textColor: (tab && tab.enrollStatus === "completed") ? ThemeBackend.crust : ThemeBackend.text
                cornerRadius: ThemeBackend.borderRadius
                onTriggered: {
                    if (tab) {
                        if (tab.enrollStatus === "completed") {
                            enrollPopup.close();
                        } else {
                            tab.cancelEnrollment();
                        }
                    }
                }
            }
        }
    }
}
