import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import "../../"
import "../"

Notification {
    id: faceRoot

    fullSummary: model ? (model.summary || I18n.t("notifications.types.default.fallback_summary")) : ""
    fullBody: model ? (model.body || "") : ""

    iconArea: [
        Item {
            anchors.fill: parent

            Image {
                id: notifIcon
                anchors.fill: parent
                source: {
                    let ic = model ? (model.icon || model.iconPath || "") : "";
                    return AppMatcher.iconSource(ic);
                }
                smooth: true
                mipmap: true
                sourceSize: {
                    let s = Math.max(48, Math.ceil(Math.max(width, height) * (Screen.devicePixelRatio || 1)));
                    return Qt.size(s, s);
                }
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready && source !== "" && !AppMatcher.iconMissing(source)
            }

            Text {
		anchors.centerIn: parent
		anchors.horizontalCenterOffset: 1
		anchors.verticalCenterOffset: -1
                visible: !notifIcon.visible
                text: "󰋽"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: s(22)
                color: faceRoot.bodyText
            }
        }
    ]

    headerArea: [
        Text {
            Layout.fillWidth: true
            horizontalAlignment: I18n.textAlignment
            text: model ? (model.displayName || model.appName || "System") : "System"
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: s(11)
            color: faceRoot.bodyText
            elide: Text.ElideRight
        }
    ]
}
