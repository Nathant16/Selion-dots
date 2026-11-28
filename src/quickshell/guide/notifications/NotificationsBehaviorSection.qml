import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

SettingsBlob {
    id: sectionRoot
    required property var tab
    readonly property var rootObj: tab.rootObj

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "notifications_dnd"
        searchKeywords: "notifications do not disturb dnd silent mute pause hide"
        icon: "󰂛"
        title: I18n.t("guide.notifications.dnd.title")
        description: I18n.t("guide.notifications.dnd.desc")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: sectionRoot.tab.dnd
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                sectionRoot.tab.updateNotifSetting("dnd", c);
            }
        }
    }

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "notifications_empty_graphic"
        searchKeywords: "notifications center empty illustration graphic image placeholder"
        icon: "󰋑"
        title: I18n.t("guide.notifications.empty_graphic.title")
        description: I18n.t("guide.notifications.empty_graphic.desc")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: sectionRoot.tab.showEmptyGraphic
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                sectionRoot.tab.updateNotifSetting("showEmptyGraphic", c);
            }
        }
    }

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "notifications_right_click_close"
        searchKeywords: "notifications right click dismiss close mouse button"
        icon: "󰍽"
        title: I18n.t("guide.notifications.right_click_close.title", "Close with right click")
        description: I18n.t("guide.notifications.right_click_close.desc", "Dismiss a notification by right-clicking it")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: sectionRoot.tab.rightClickClose
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                sectionRoot.tab.updateNotifSetting("rightClickClose", c);
            }
        }
    }
}
