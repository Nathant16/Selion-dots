import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

SettingsBlob {
    id: sectionRoot
    required property var tab
    readonly property var rootObj: tab.rootObj
    property alias avatarDropdown: avatarDropdown
    property alias langDropdown: langDropdown

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "general_avatar"
        icon: "󰀄"
        title: I18n.t("guide.general.avatar.title") || "Profile picture"
        description: I18n.t("guide.general.avatar.desc") || "Choose profile picture"
        searchKeywords: "avatar profile picture photo user icon image"

        RowLayout {
            spacing: rootObj.s(12)

            ColumnLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: rootObj.s(8)

                ClickButton {
                    Layout.alignment: Qt.AlignRight
                    implicitHeight: rootObj.s(32)
                    buttonText: I18n.t("guide.general.avatar.select")
                    buttonIcon: "󰉋"
                    accentColor: ThemeBackend.mauve
                    textColor: ThemeBackend.crust
                    cornerRadius: ThemeBackend.borderRadius
                    horizontalPadding: rootObj.s(14)
                    iconFontSize: rootObj.s(15)
                    textFontSize: rootObj.s(11)
                    onTriggered: sectionRoot.tab.openImagePicker(sectionRoot.tab.currentAvatarSourcePath)
                }

                PathDropdown {
                    id: avatarDropdown
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: rootObj.s(280)
                    implicitHeight: rootObj.s(32)
                    options: sectionRoot.tab.currentAvatarSourcePath !== "" ? [sectionRoot.tab.currentAvatarSourcePath] : []
                    currentIndex: 0
                    fuzzySearch: true
                    placeholderText: sectionRoot.tab.currentAvatarSourcePath !== "" ? sectionRoot.tab.currentAvatarSourcePath : I18n.t("guide.general.avatar.placeholder", "Select image path...")
                    fontFamily: ThemeBackend.fontFamily
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
                        sectionRoot.tab.setGeneralSetting("avatarPath", value);
                    }
                    onSelected: function(index, value) {
                        sectionRoot.tab.setGeneralSetting("avatarPath", value);
                    }
                }
            }

            AvatarPreview {
                tab: sectionRoot.tab
            }
        }
    }

    SettingsRow {
        rootObj: sectionRoot.tab.rootObj
        settingId: "general_language"
        searchKeywords: "language locale translation i18n english interface region"
        icon: "󰗊"
        title: I18n.t("guide.general.language.title")
        description: I18n.t("guide.general.language.desc")

        Dropdown {
            id: langDropdown
            implicitWidth: rootObj.s(180)
            implicitHeight: rootObj.s(32)
            options: sectionRoot.tab.languageNames
            currentIndex: {
                let idx = sectionRoot.tab.languageCodes.indexOf(sectionRoot.tab.currentLanguage);
                return idx !== -1 ? idx : 0;
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
            onValueChanged: function(index, value) {
                sectionRoot.tab.setGeneralSetting("language", sectionRoot.tab.languageCodes[index]);
            }
        }
    }
}
