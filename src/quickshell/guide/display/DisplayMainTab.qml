import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../"
import "../../reusables"

DisplayMainState {
    id: displayTabRoot
    subTabIndex: 0

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(8)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
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
            spacing: rootObj.s(12)

            // 2D Monitor Stage & Layout Overview
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rootObj.s(150)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.4)
                clip: true

                GlassFill {
                    anchors.fill: parent
                    radius: parent.radius
                    tintColor: Qt.alpha(ThemeBackend.surface0, 0.4)
                    tintAmount: 0.25
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: rootObj.s(12)
                    spacing: rootObj.s(8)

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.t("guide.display.layout_stage", "2D Расположение мониторов")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(13)
                            font.bold: true
                            color: ThemeBackend.text
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: displayTabRoot.monitorsList.length + " " + I18n.t("guide.display.monitors_detected", "монитор(ов)")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }

                    // 2D Canvas Stage
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: rootObj.s(8)
                        color: Qt.alpha(ThemeBackend.crust, 0.4)
                        border.width: 1
                        border.color: Qt.alpha(ThemeBackend.surface1, 0.5)

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: rootObj.s(14)

                            Repeater {
                                model: displayTabRoot.monitorsList
                                delegate: Rectangle {
                                    readonly property var mDims: modelData.dimensions ? modelData.dimensions.split("x") : ["1920", "1080"]
                                    readonly property real rawW: parseFloat(mDims[0]) || 1920
                                    readonly property real rawH: parseFloat(mDims[1]) || 1080
                                    readonly property real aspect: rawW / (rawH || 1)
                                    implicitHeight: rootObj.s(70)
                                    implicitWidth: Math.max(rootObj.s(90), Math.min(rootObj.s(160), implicitHeight * aspect))
                                    radius: rootObj.s(6)
                                    color: modelData.active !== false ? Qt.alpha(ThemeBackend.surface1, 0.7) : Qt.alpha(ThemeBackend.surface0, 0.3)
                                    border.width: 2
                                    border.color: modelData.active !== false ? ThemeBackend.mauve : ThemeBackend.surface2

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: rootObj.s(2)

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.name || "Display"
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            font.bold: true
                                            color: ThemeBackend.text
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: (modelData.dimensions || "1920x1080") + " (" + (modelData.scale || 1.0) + "x)"
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(9)
                                            color: ThemeBackend.subtext0
                                        }

                                        Rectangle {
                                            Layout.alignment: Qt.AlignHCenter
                                            implicitHeight: rootObj.s(14)
                                            implicitWidth: stageBadgeText.implicitWidth + rootObj.s(10)
                                            radius: rootObj.s(7)
                                            color: modelData.active !== false ? Qt.alpha(ThemeBackend.green, 0.2) : Qt.alpha(ThemeBackend.surface2, 0.4)

                                            Text {
                                                id: stageBadgeText
                                                anchors.centerIn: parent
                                                text: modelData.active !== false ? "ON" : "OFF"
                                                font.pixelSize: rootObj.s(8)
                                                font.bold: true
                                                color: modelData.active !== false ? ThemeBackend.green : ThemeBackend.subtext0
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: displayTabRoot.monitorsList
                delegate: DisplayMonitorCard { tab: displayTabRoot }
            }
        }
    }
}
