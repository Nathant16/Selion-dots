import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../"
import "../../reusables"
import "../../reusables/guide"

SettingsBlob {
    id: sectionRoot
    required property var tab
    readonly property var rootObj: tab.rootObj
    property alias soundDropdown: soundDropdown

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "notifications_sound"
        searchKeywords: "notifications sound audio chime ping alert tone"
        icon: "󰂚"
        title: I18n.t("guide.notifications.sound.title")
        description: I18n.t("guide.notifications.sound.desc")

        Toggle {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: sectionRoot.tab.soundEnabled
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                sectionRoot.tab.updateNotifSetting("sound", c);
            }
        }
    }

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "notifications_sound_file"
        searchKeywords: "notifications sound file ringtone chime wav ogg mp3 custom audio"
        visible: sectionRoot.tab.soundEnabled
        icon: "󰎆"
        title: I18n.t("guide.notifications.sound_file.title")
        description: I18n.t("guide.notifications.sound_file.desc")

        IconButton {
            Layout.preferredWidth: rootObj.s(32)
            Layout.preferredHeight: rootObj.s(32)
            Layout.alignment: Qt.AlignVCenter
            cornerRadius: rootObj.s(6)
            buttonIcon: "󰉋"
            iconFontSize: rootObj.s(14)
            accentColor: ThemeBackend.surface0
            textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
            onClicked: {
                let userSoundsPath = Caching.stateDir + "/sounds/notifications";
                let escapeBash = function(str) { return String(str).replace(/(["\\$`])/g, '\\$1'); };
                Quickshell.execDetached(["bash", "-c", "mkdir -p \"" + escapeBash(userSoundsPath) + "\" && xdg-open \"" + escapeBash(userSoundsPath) + "\""]);
            }
        }

        IconButton {
            Layout.preferredWidth: rootObj.s(32)
            Layout.preferredHeight: rootObj.s(32)
            Layout.alignment: Qt.AlignVCenter
            cornerRadius: rootObj.s(6)
            buttonIcon: "󰐕"
            iconFontSize: rootObj.s(14)
            accentColor: ThemeBackend.surface0
            textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
            onClicked: sectionRoot.tab.soundPickerPopup.openPicker()
        }

        Dropdown {
            id: soundDropdown
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: rootObj.s(180)
            Layout.preferredHeight: rootObj.s(32)
            options: sectionRoot.tab.availableSounds
            currentIndex: {
                for (let i = 0; i < sectionRoot.tab.soundList.length; i++) {
                    if (sectionRoot.tab.soundList[i].path === sectionRoot.tab.selectedSound) {
                        return i;
                    }
                }
                return 0;
            }
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface0
            hoverColor: ThemeBackend.surface1
            dropdownColor: ThemeBackend.surface0
            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
            textColor: ThemeBackend.text
            activeTextColor: ThemeBackend.crust
            cornerRadius: ThemeBackend.borderRadius
            fontPixelSize: rootObj.s(11)
            onSelected: function(index, value) {
                if (index >= 0 && index < sectionRoot.tab.soundList.length) {
                    let targetPath = sectionRoot.tab.soundList[index].path;
                    sectionRoot.tab.updateNotifSetting("soundFile", targetPath);
                    if (typeof Sounds !== "undefined" && typeof Sounds.play === "function") {
                        Sounds.play(targetPath);
                    }
                }
            }
        }
    }
}
