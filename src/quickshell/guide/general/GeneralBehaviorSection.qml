import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

SettingsBlob {
    id: section
    required property var tab
    readonly property var rootObj: tab.rootObj

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "general_uiscale"
        searchKeywords: "quickshell ui scale interface zoom panel bar widgets launcher settings hidpi fractional mango"
        icon: "󰍍"
        title: I18n.t("guide.general.uiscale.title", "Quickshell UI Scale")
        description: I18n.t("guide.general.uiscale.desc", "Scale top bar, widgets, launcher and settings independently of WM display scale")

        Draggable {
            id: shellUiScaleSlider
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.rightMargin: rootObj.s(8)
            implicitWidth: rootObj.s(220)
            implicitHeight: rootObj.s(18)
            from: 50
            to: 200
            stepSize: 5
            defaultValue: 100
            showValueBubble: true
            valueFormatter: function(v) { return Math.round(v) + "%" }
            value: Math.round(section.tab.uiScale * 100)
            backgroundColor: ThemeBackend.surface0
            accentColor: ThemeBackend.mauve
            handleColor: ThemeBackend.text
            handleBorderColor: ThemeBackend.mantle
            onMoved: function(val) {
                let scaleVal = Math.round(val) / 100.0;
                if (Math.abs(section.tab.uiScale - scaleVal) > 0.001) {
                    section.tab.uiScale = scaleVal;
                    section.tab.uiScaleDebounceTimer.restart();
                }
            }
            onDragFinished: {
                section.tab.uiScaleDebounceTimer.stop();
                section.tab.updateGeneralSettings();
            }
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        settingId: "general_quickactions"
        searchKeywords: "quick actions quickactions floating overlay calculator notes timer draw converter edge"
        icon: "󱓞"
        title: I18n.t("guide.general.quickactions.title") || "Quickactions"
        description: I18n.t("guide.general.quickactions.desc") || "Enable floating quickactions overlay"

        Toggle {
            checked: section.tab.quickactions
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                section.tab.quickactions = c;
                section.tab.updateGeneralSettings();
            }
        }
    }
}
