import QtQuick
import QtQuick.Layouts
import "../../../"
import "../../../reusables"
import "../../../reusables/guide"

SettingsBlob {
    id: sectionRoot
    required property var tab
    readonly property var rootObj: tab.rootObj

    SettingsGroup {
        rootObj: sectionRoot.tab.rootObj
        settingId: "bar_style"
        searchKeywords: "bar style appearance modular solid fill floating panel"
        icon: "󰏘"
        title: I18n.t("guide.bar.style.title")
        description: I18n.t("guide.bar.style.desc")
        expanded: sectionRoot.tab.barStyle === "solid" || sectionRoot.tab.barStyle === "fill"

        Switch {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            implicitWidth: rootObj.s(210)
            implicitHeight: rootObj.s(32)
            options: [I18n.t("guide.bar.style.modular"), I18n.t("guide.bar.style.solid"), I18n.t("guide.bar.style.fill")]
            currentIndex: sectionRoot.tab.barStyle === "fill" ? 2 : (sectionRoot.tab.barStyle === "solid" ? 1 : 0)
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface0
            textColor: ThemeBackend.subtext0
            activeTextColor: ThemeBackend.crust
            cornerRadius: ThemeBackend.borderRadius
            fontPixelSize: rootObj.s(11)
            onToggled: function(index) {
                sectionRoot.tab.clearPendingGroup();
                let st = "modular";
                if (index === 1) st = "solid";
                else if (index === 2) st = "fill";
                sectionRoot.tab.setBarSetting("style", st);
            }
        }

        subSettings: [
            SettingsRow {
                rootObj: sectionRoot.tab.rootObj
                settingId: "bar_distinct_pills"
                searchKeywords: "bar pills modules separate cards capsules solid fill"
                icon: "󰍜"
                title: I18n.t("guide.bar.distinct_pills.title")
                description: I18n.t("guide.bar.distinct_pills.desc")

                Toggle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    checked: sectionRoot.tab.distinctPills
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface1
                    handleColor: ThemeBackend.crust
                    handleOffColor: ThemeBackend.text
                    onToggled: function(c) {
                        sectionRoot.tab.clearPendingGroup();
                        sectionRoot.tab.setBarSetting("distinctPills", c);
                    }
                }
            }
        ]
    }
}
