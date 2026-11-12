import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

GuideTab {
    id: packagesTabRoot
    deferredStages: 4

    property var categories: [
        {
            "id": "browsers",
            "title": I18n.t("guide.packages.categories.browsers", "Web Browsers"),
            "desc": I18n.t("guide.packages.categories.browsers_desc", "Modern, privacy-respecting and styled browsers"),
            "icon": "󰈹",
            "packages": [
                { "name": "Zen Browser", "pkg": "zen-browser-bin", "desc": "Firefox-based browser with vertical tabs and theme support", "icon": "󰈹" },
                { "name": "Brave Browser", "pkg": "brave-bin", "desc": "Chromium-based privacy browser with adblocking", "icon": "󰖟" },
                { "name": "Mozilla Firefox", "pkg": "firefox", "desc": "Standard open-source web browser", "icon": "󰈹" }
            ]
        },
        {
            "id": "development",
            "title": I18n.t("guide.packages.categories.development", "Development & Editors"),
            "desc": I18n.t("guide.packages.categories.development_desc", "Code editors and development environments"),
            "icon": "󰅩",
            "packages": [
                { "name": "Visual Studio Code", "pkg": "visual-studio-code-bin", "desc": "Extensible code editor with dynamic Matugen theming", "icon": "󰨞" },
                { "name": "Zed Editor", "pkg": "zed", "desc": "High-performance multiplayer code editor written in Rust", "icon": "󰅩" },
                { "name": "Neovim", "pkg": "neovim", "desc": "Vim-fork focused on extensibility and usability", "icon": "󰞋" }
            ]
        },
        {
            "id": "social",
            "title": I18n.t("guide.packages.categories.social", "Social & Communication"),
            "desc": I18n.t("guide.packages.categories.social_desc", "Instant messaging, communities, and note taking"),
            "icon": "󰭹",
            "packages": [
                { "name": "AyuGram Desktop", "pkg": "ayugram-desktop-bin", "desc": "Feature-rich Telegram desktop client with theme support", "icon": "󰭹" },
                { "name": "Vesktop", "pkg": "vesktop-bin", "desc": "Custom Discord client with Vencord and Wayland screen share", "icon": "󰙯" },
                { "name": "Obsidian", "pkg": "obsidian", "desc": "Knowledge base and markdown note-taking app", "icon": "󱓧" }
            ]
        },
        {
            "id": "media",
            "title": I18n.t("guide.packages.categories.media", "Media & Gaming"),
            "desc": I18n.t("guide.packages.categories.media_desc", "Audio players, gaming clients, and media tools"),
            "icon": "󰓇",
            "packages": [
                { "name": "Spotify", "pkg": "spotify", "desc": "Digital music streaming service with Spicetify theme integration", "icon": "󰓇" },
                { "name": "Steam", "pkg": "steam", "desc": "Digital game distribution platform", "icon": "󰓓" },
                { "name": "Prism Launcher", "pkg": "prismlauncher", "desc": "Custom Minecraft launcher with modpack management", "icon": "󰍳" }
            ]
        }
    ]

    ColumnLayout {
        width: parent.width
        spacing: s(24)

        GuideHeader {
            title: I18n.t("guide.tabs.packages", "Additional Packages")
            description: I18n.t("guide.packages.desc", "Select additional software categories and applications configured with matching system themes.")
        }

        Repeater {
            model: packagesTabRoot.categories

            delegate: GuideCard {
                id: categoryCard
                required property var modelData

                settingId: "packages_cat_" + modelData.id
                title: modelData.title
                description: modelData.desc
                searchKeywords: "packages " + modelData.id + " " + modelData.title

                ColumnLayout {
                    width: parent.width
                    spacing: s(12)

                    Repeater {
                        model: categoryCard.modelData.packages

                        delegate: Rectangle {
                            id: pkgRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: s(52)
                            color: "transparent"
                            radius: s(8)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: s(8)
                                anchors.rightMargin: s(8)
                                spacing: s(12)

                                Text {
                                    text: pkgRow.modelData.icon || "󰏔"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: s(18)
                                    color: Colors.accent
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: s(2)

                                    Text {
                                        text: pkgRow.modelData.name
                                        font.pixelSize: s(13)
                                        font.weight: Font.Medium
                                        color: Colors.text
                                    }

                                    Text {
                                        text: pkgRow.modelData.desc
                                        font.pixelSize: s(11)
                                        color: Colors.textSecondary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Text {
                                    text: pkgRow.modelData.pkg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: s(11)
                                    color: Colors.textMuted
                                    Layout.rightMargin: s(8)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

