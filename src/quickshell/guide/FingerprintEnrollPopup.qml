import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import "../"
import "../reusables"
import "../reusables/buttons"
import "../reusables/inputs"
import "../reusables/display"

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

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.92; to: 1.0; duration: 240; easing.type: Easing.OutBack }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 180; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.94; duration: 180; easing.type: Easing.InQuad }
        }
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.45)
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

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
        color: popupGlass.active
            ? "transparent"
            : (ThemeBackend.glassActive
                ? Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
                : ThemeBackend.base)
        border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
        border.width: 1

        WallpaperBlur {
            id: popupBlur
            z: -1
            anchors.fill: parent
            radius: parent.radius
            standalone: true
            surfaceEnabled: ThemeBackend.glassActive
        }

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

                // Subtitle: only shown while enrolling to display finger name, removed "Select a finger..."
                Text {
                    Layout.fillWidth: true
                    visible: tab && tab.isEnrolling
                    text: (tab && tab.isEnrolling) ? tab.getFingerLabel(tab.selectedFingerName) : ""
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

        // Central Fingerprint Icon with radial fill from center
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: rootObj ? rootObj.s(110) : 110
            implicitHeight: rootObj ? rootObj.s(110) : 110

            // Outer reactive pulse glow ring
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * (tab ? tab.iconPulseScale : 1.0)
                height: width
                radius: width / 2
                color: Qt.alpha(tab ? tab.iconCurrentColor : ThemeBackend.mauve, 0.12)
                Behavior on color { ColorAnimation { duration: 250 } }
            }

            // Central circle container (supports transparent and solid themes)
            Rectangle {
                id: stageCircle
                anchors.centerIn: parent
                width: rootObj ? rootObj.s(96) : 96
                height: width
                radius: width / 2
                color: circleGlass.active
                    ? "transparent"
                    : (ThemeBackend.glassActive
                        ? Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity * 0.75)
                        : ThemeBackend.surface0)
                border.color: Qt.alpha(tab ? tab.iconCurrentColor : ThemeBackend.mauve, 0.35)
                border.width: 2
                clip: true
                Behavior on border.color { ColorAnimation { duration: 200 } }

                GlassFill {
                    id: circleGlass
                    anchors.fill: parent
                    radius: parent.radius
                    tintColor: ThemeBackend.surface0
                    tintAmount: 0.25
                }

                // 1. Base muted glyph (unfilled outline)
                Text {
                    id: baseGlyph
                    anchors.centerIn: parent
                    text: "󰈷"
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: rootObj ? rootObj.s(52) : 52
                    scale: tab ? tab.iconPulseScale : 1.0
                    color: Qt.alpha(ThemeBackend.text, 0.22)
                    transform: Translate { x: tab ? tab.iconShakeX : 0.0 }
                }

                // 2. Active colored glyph (source for radial fill mask)
                Item {
                    id: filledSource
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true

                    Text {
                        anchors.centerIn: parent
                        text: "󰈷"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: rootObj ? rootObj.s(52) : 52
                        scale: tab ? tab.iconPulseScale : 1.0
                        color: (tab && tab.enrollStatus === "completed") ? ThemeBackend.green : (tab ? tab.iconCurrentColor : ThemeBackend.mauve)
                        transform: Translate { x: tab ? tab.iconShakeX : 0.0 }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                // 3. Mask circle expanding from center
                Item {
                    id: maskSourceItem
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true

                    Rectangle {
                        id: maskCircle
                        anchors.centerIn: parent
                        property real maxRadius: (rootObj ? rootObj.s(42) : 42)
                        property real targetRadius: {
                            if (!tab) return 0;
                            if (tab.enrollStatus === "completed") return stageCircle.width;
                            if (tab.currentPercent <= 0) return 0;
                            return maxRadius * Math.sqrt(tab.currentPercent / 100.0);
                        }
                        width: Math.max(0, targetRadius * 2)
                        height: width
                        radius: targetRadius
                        color: "black"

                        Behavior on targetRadius {
                            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                        }
                    }
                }

                // 4. MultiEffect rendering the colored glyph filled from center outwards
                MultiEffect {
                    anchors.fill: parent
                    source: filledSource
                    maskEnabled: true
                    maskSource: maskSourceItem
                    visible: (tab && (tab.currentPercent > 0 || tab.enrollStatus === "completed"))
                }

                // 5. Success floating badge (clean, elegant checkmark, replaces the awkward checkbox)
                Rectangle {
                    id: successBadge
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: rootObj ? rootObj.s(6) : 6
                    width: rootObj ? rootObj.s(24) : 24
                    height: width
                    radius: width / 2
                    color: ThemeBackend.green
                    border.color: ThemeBackend.base
                    border.width: 2
                    visible: tab && tab.enrollStatus === "completed"
                    scale: visible ? 1.0 : 0.0
                    opacity: visible ? 1.0 : 0.0

                    Behavior on scale {
                        NumberAnimation { duration: 320; easing.type: Easing.OutBack }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 220 }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰄬"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: rootObj ? rootObj.s(13) : 13
                        font.weight: Font.Bold
                        color: ThemeBackend.crust
                    }
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

        // Progress bar & Stage indicator (10 stages)
        ColumnLayout {
            Layout.fillWidth: true
            visible: tab && (tab.isEnrolling || tab.enrollStatus === "completed")
            spacing: rootObj ? rootObj.s(6) : 6

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: I18n.t("guide.fingerprint.modal.stage_info", "Stage %1 of %2 (%3%)")
                    .arg(tab ? tab.currentStage : 0)
                    .arg(tab ? tab.enrollStages : 10)
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
                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
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

                // Cancel button without icon (standard across Serpantinum dialogs)
                ClickButton {
                    Layout.fillWidth: true
                    implicitHeight: rootObj ? rootObj.s(34) : 34
                    buttonText: I18n.t("guide.fingerprint.modal.cancel", "Cancel")
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    cornerRadius: ThemeBackend.borderRadius
                    onTriggered: enrollPopup.close()
                }

                // Start scan action button
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
                buttonIcon: (tab && tab.enrollStatus === "completed") ? "󰄬" : "󰅖"
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
