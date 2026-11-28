import QtQuick
import QtQuick.Layouts
import "../../../"
import "../../../reusables"
import "../../../reusables/guide"

SettingsBlob {
    id: sectionRoot
    required property var tab
    readonly property var rootObj: tab.rootObj
    property alias barPosDropdown: barPosDropdown
    property alias barMonitorSelector: barMonitorSelector

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "bar_position"
        searchKeywords: "bar position placement side edge top bottom left right sidebar"
        icon: "󱂬"
        title: I18n.t("guide.bar.position.title")
        description: I18n.t("guide.bar.position.desc")

        Dropdown {
            id: barPosDropdown
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            implicitWidth: rootObj.s(180)
            implicitHeight: rootObj.s(32)
            options: [I18n.t("guide.bar.position.top"), I18n.t("guide.bar.position.bottom"), I18n.t("guide.bar.position.left"), I18n.t("guide.bar.position.right")]
            currentIndex: sectionRoot.tab.barPosition === "bottom" ? 1 : (sectionRoot.tab.barPosition === "left" ? 2 : (sectionRoot.tab.barPosition === "right" ? 3 : 0))
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface0
            hoverColor: ThemeBackend.surface1
            dropdownColor: ThemeBackend.surface0
            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
            textColor: ThemeBackend.text
            activeTextColor: ThemeBackend.crust
            cornerRadius: ThemeBackend.borderRadius
            fontPixelSize: rootObj.s(11)
            onValueChanged: function(index, value) {
                sectionRoot.tab.clearPendingGroup();
                let pos = "top";
                if (index === 1) pos = "bottom";
                else if (index === 2) pos = "left";
                else if (index === 3) pos = "right";
                sectionRoot.tab.setBarSetting("position", pos);
            }
        }
    }

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "bar_monitors"
        searchKeywords: "bar monitors displays screens outputs multi-monitor visibility show hide"
        icon: "󰍹"
        title: I18n.t("guide.bar.monitors.title", "Monitors")
        description: I18n.t("guide.bar.monitors.desc", "Select which monitors display the bar")

        MonitorSelector {
            id: barMonitorSelector
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            allowEmpty: true
            manageSelection: false
            selectedMonitors: sectionRoot.tab.barMonitors
            buttonHeight: rootObj.s(32)
            buttonCornerRadius: rootObj.s(8)
            buttonHorizontalPadding: rootObj.s(12)
            textFontSize: Math.round(rootObj.s(11))
            spacing: rootObj.s(8)
            activeColor: ThemeBackend.mauve
            activeTextColor: ThemeBackend.crust
            inactiveColor: ThemeBackend.surface1
            inactiveTextColor: ThemeBackend.text
            bgOpacity: 1.0
            onSelectionChanged: function(selected) {
                sectionRoot.tab.clearPendingGroup();
                sectionRoot.tab.setBarMonitors(selected);
            }
        }
    }

    SettingsRow {
        id: widthInnerBox
        rootObj: sectionRoot.tab.rootObj
        settingId: "bar_width"
        searchKeywords: "bar width height length size percentage span"
        icon: "󰘖"
        title: {
            if (sectionRoot.tab.barPosition === "left" || sectionRoot.tab.barPosition === "right") {
                let h = I18n.t("guide.bar.height.title");
                if (h && h !== "guide.bar.height.title") return h;
                let w = I18n.t("guide.bar.width.title");
                if (w && w.indexOf("Width") !== -1) return w.replace("Width", "Height");
                if (w && w.indexOf("width") !== -1) return w.replace("width", "height");
                return w;
            }
            return I18n.t("guide.bar.width.title");
        }
        description: {
            if (sectionRoot.tab.barPosition === "left" || sectionRoot.tab.barPosition === "right") {
                let h = I18n.t("guide.bar.height.desc");
                if (h && h !== "guide.bar.height.desc") return h;
                let w = I18n.t("guide.bar.width.desc");
                if (w && w.indexOf("Width") !== -1) return w.replace("Width", "Height");
                if (w && w.indexOf("width") !== -1) return w.replace("width", "height");
                return w;
            }
            return I18n.t("guide.bar.width.desc");
        }

        Draggable {
            id: barWidthSlider
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.rightMargin: rootObj.s(8)
            implicitWidth: rootObj.s(220)
            implicitHeight: rootObj.s(18)
            from: 5
            to: 100
            stepSize: 1
            defaultValue: 100
            showValueBubble: true
            valueFormatter: function(v) { return Math.round(v) + "%" }
            value: sectionRoot.tab.currentBarWidth
            backgroundColor: ThemeBackend.surface0
            accentColor: ThemeBackend.mauve
            handleColor: ThemeBackend.text
            handleBorderColor: ThemeBackend.mantle
            onMoved: function(val) {
                sectionRoot.tab.clearPendingGroup();
                let rounded = Math.round(val);
                if (sectionRoot.tab.currentBarWidth !== rounded) {
                    sectionRoot.tab.setBarSettingDebounced("width", rounded);
                }
            }
            onDragFinished: {
                sectionRoot.tab.flushBarSettings();
            }
        }
    }

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "bar_thickness"
        searchKeywords: "bar thickness height size scale slim compact tall"
        icon: "󰘖"
        title: I18n.t("guide.bar.thickness.title", "Bar thickness")
        description: I18n.t("guide.bar.thickness.desc", "Change how thick the bar is, modules scale to fit")

        Draggable {
            id: barThicknessSlider
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.rightMargin: rootObj.s(8)
            implicitWidth: rootObj.s(220)
            implicitHeight: rootObj.s(18)
            from: 28
            to: 48
            stepSize: 1
            defaultValue: 40
            showValueBubble: true
            valueFormatter: function(v) { return Math.round(v / 40 * 100) + "%" }
            value: sectionRoot.tab.currentBarThickness
            backgroundColor: ThemeBackend.surface0
            accentColor: ThemeBackend.mauve
            handleColor: ThemeBackend.text
            handleBorderColor: ThemeBackend.mantle
            onMoved: function(val) {
                sectionRoot.tab.clearPendingGroup();
                let rounded = Math.round(val);
                if (sectionRoot.tab.currentBarThickness !== rounded) {
                    sectionRoot.tab.setBarSettingDebounced("height", rounded);
                }
            }
            onDragFinished: {
                sectionRoot.tab.flushBarSettings();
            }
        }
    }

    SettingsRow {
        id: centerByEdgesBox
        rootObj: sectionRoot.tab.rootObj
        settingId: "bar_center_by_edges"
        searchKeywords: "bar center alignment edges balance modules middle"
        icon: "󰉹"
        title: I18n.t("guide.bar.center_by_edges.title")
        description: (sectionRoot.tab.barPosition === "left" || sectionRoot.tab.barPosition === "right") ? I18n.t("guide.bar.center_by_edges.desc_vertical") : I18n.t("guide.bar.center_by_edges.desc")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: sectionRoot.tab.centerByEdges
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                sectionRoot.tab.clearPendingGroup();
                sectionRoot.tab.setBarSetting("centerByEdges", c);
            }
        }
    }
}
