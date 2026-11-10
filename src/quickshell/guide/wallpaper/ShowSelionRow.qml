import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

SettingsRow {
    id: row
    required property var tab

    rootObj: row.tab.rootObj
    settingId: "show_selion_wallpapers"
    icon: "󰉏"
    title: I18n.t("guide.theme.wallpaper.show_selion.title", "Show Selion wallpapers")
    description: I18n.t("guide.theme.wallpaper.show_selion.desc", "Include the built-in Selion wallpaper pack alongside your custom wallpapers")
    searchKeywords: "selion built-in wallpapers pack show hide toggle directory"

    Toggle {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        checked: row.tab.showSelionWallpapers
        accentColor: ThemeBackend.mauve
        baseColor: ThemeBackend.surface1
        handleColor: ThemeBackend.crust
        handleOffColor: ThemeBackend.text
        onToggled: function(c) {
            row.tab.updateShowSelionWallpapers(c);
        }
    }
}

