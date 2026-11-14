import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/buttons"
import "../reusables/inputs"
import "../reusables/guide"

GuideTab {
    id: keybindingsTabRoot

    property string currentCategory: "all"
    property string searchQuery: ""
    property var standardList: []
    property var customList: []
    property string activeCompositor: (typeof Compositor !== "undefined" && Compositor.name) ? Compositor.name : "hyprland"
    property bool editorOpen: false

    property string editingId: ""
    property bool isEditingStandard: false
    property string newKey: ""
    property string newExec: ""
    property string newTitle: ""

    function s(val) {
        return rootObj ? rootObj.s(val) : val;
    }

    Process {
        id: kbLoader
        command: ["python3", Caching.serpantinumDir + "/scripts/keybindings_manager.py", "list"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                try {
                    let res = JSON.parse(data.trim());
                    if (res) {
                        keybindingsTabRoot.standardList = res.standard || [];
                        keybindingsTabRoot.customList = res.custom || [];
                        if (res.compositor) keybindingsTabRoot.activeCompositor = res.compositor;
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: kbAction
        property var onCompleteCallback: null
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                kbLoader.running = true;
                if (kbAction.onCompleteCallback) {
                    kbAction.onCompleteCallback();
                    kbAction.onCompleteCallback = null;
                }
            }
        }
    }

    function openNewCustomEditor() {
        editingId = "";
        isEditingStandard = false;
        newKey = "";
        newExec = "";
        newTitle = "";
        editorOpen = true;
    }

    function startEditing(item) {
        editingId = item.id || "";
        isEditingStandard = !item.isCustom;
        newKey = Array.isArray(item.keys) ? item.keys.join(" + ") : (item.key || "");
        newExec = item.exec || "";
        newTitle = item.title || "";
        editorOpen = true;
    }

    function saveKeybinding() {
        if (!newKey.trim()) return;
        let k = newKey.trim();
        let e = newExec.trim();
        let t = newTitle.trim() ? newTitle.trim() : e;

        if (editingId !== "") {
            if (isEditingStandard) {
                kbAction.command = ["python3", Caching.serpantinumDir + "/scripts/keybindings_manager.py", "override", editingId, k];
            } else {
                kbAction.command = ["python3", Caching.serpantinumDir + "/scripts/keybindings_manager.py", "override", editingId, k, e, t];
            }
        } else {
            if (!e) return;
            kbAction.command = ["python3", Caching.serpantinumDir + "/scripts/keybindings_manager.py", "add", k, e, t];
        }

        kbAction.onCompleteCallback = function() {
            editingId = "";
            isEditingStandard = false;
            newKey = "";
            newExec = "";
            newTitle = "";
            editorOpen = false;
        };
        kbAction.running = true;
    }

    function resetStandardKeybinding(id) {
        if (!id) return;
        kbAction.command = ["python3", Caching.serpantinumDir + "/scripts/keybindings_manager.py", "reset", id];
        kbAction.running = true;
    }

    function deleteCustomKeybinding(id) {
        if (!id) return;
        kbAction.command = ["python3", Caching.serpantinumDir + "/scripts/keybindings_manager.py", "delete", id];
        kbAction.running = true;
    }

    onVisibleChanged: {
        if (visible && !kbLoader.running) {
            kbLoader.running = true;
        }
    }

    Component.onCompleted: {
        kbLoader.running = true;
    }

    readonly property var allItems: {
        let list = [];
        let q = searchQuery.trim().toLowerCase();
        let cat = currentCategory;

        // Custom items
        for (let i = 0; i < customList.length; i++) {
            let item = customList[i];
            let obj = {
                id: item.id || ("custom_" + i),
                cat: "custom",
                keys: typeof item.key === "string" ? item.key.split("+").map(k => k.trim()) : [item.key],
                title: item.title || item.exec,
                desc: item.desc || item.exec,
                exec: item.exec,
                isCustom: true,
                isOverridden: false
            };
            if (cat !== "all" && cat !== "custom") continue;
            if (q) {
                let match = (obj.title.toLowerCase().indexOf(q) !== -1) ||
                            (obj.desc.toLowerCase().indexOf(q) !== -1) ||
                            (obj.keys.join(" ").toLowerCase().indexOf(q) !== -1);
                if (!match) continue;
            }
            list.push(obj);
        }

        // Standard items
        for (let i = 0; i < standardList.length; i++) {
            let item = standardList[i];
            if (cat !== "all" && cat !== item.cat) continue;
            if (q) {
                let match = (item.title && item.title.toLowerCase().indexOf(q) !== -1) ||
                            (item.desc && item.desc.toLowerCase().indexOf(q) !== -1) ||
                            (item.keys && item.keys.join(" ").toLowerCase().indexOf(q) !== -1);
                if (!match) continue;
            }
            list.push(item);
        }
        return list;
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: s(12)
        contentWidth: width
        contentHeight: contentCol.implicitHeight + s(32)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            active: parent.moving || parent.movingVertically
            width: s(4)
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: s(4)
                radius: s(2)
                color: ThemeBackend.surface2
            }
        }

        ColumnLayout {
            id: contentCol
            width: parent.width
            spacing: s(14)

            // Header Banner
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: bannerCol.implicitHeight + s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.4)

                GlassFill {
                    anchors.fill: parent
                    radius: parent.radius
                    tintColor: Qt.alpha(ThemeBackend.surface0, 0.4)
                    tintAmount: 0.25
                }

                ColumnLayout {
                    id: bannerCol
                    anchors.fill: parent
                    anchors.margins: s(14)
                    spacing: s(10)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: s(10)

                        Rectangle {
                            implicitWidth: s(38)
                            implicitHeight: s(38)
                            radius: s(8)
                            color: Qt.alpha(ThemeBackend.mauve, 0.2)

                            Text {
                                anchors.centerIn: parent
                                text: "󰌌"
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: s(20)
                                color: ThemeBackend.mauve
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: s(2)

                            RowLayout {
                                spacing: s(8)
                                Text {
                                    text: I18n.t("guide.keybindings.title", "Горячие клавиши")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(16)
                                    font.bold: true
                                    color: ThemeBackend.text
                                }

                                Rectangle {
                                    implicitHeight: s(20)
                                    implicitWidth: compBadgeText.implicitWidth + s(14)
                                    radius: s(10)
                                    color: Qt.alpha(ThemeBackend.mauve, 0.25)

                                    Text {
                                        id: compBadgeText
                                        anchors.centerIn: parent
                                        text: keybindingsTabRoot.activeCompositor.toUpperCase()
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: s(10)
                                        font.bold: true
                                        color: ThemeBackend.mauve
                                    }
                                }
                            }

                            Text {
                                text: I18n.t("guide.keybindings.subtitle", "Полная шпаргалка комбинаций, синхронизированных между всеми 5 WM")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: s(11)
                                color: ThemeBackend.subtext0
                            }
                        }

                        ClickButton {
                            implicitHeight: s(32)
                            implicitWidth: s(140)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonText: editorOpen ? I18n.t("guide.keybindings.close_editor", "Закрыть") : I18n.t("guide.keybindings.add_custom", "+ Свой бинд")
                            textFontSize: s(11)
                            accentColor: editorOpen ? ThemeBackend.surface2 : ThemeBackend.mauve
                            textColor: editorOpen ? ThemeBackend.text : ThemeBackend.crust
                            onClicked: {
                                if (editorOpen) {
                                    editorOpen = false;
                                } else {
                                    openNewCustomEditor();
                                }
                            }
                        }
                    }

                    // Search input
                    Input {
                        Layout.fillWidth: true
                        implicitHeight: s(34)
                        cornerRadius: s(8)
                        baseColor: Qt.alpha(ThemeBackend.surface1, 0.5)
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.text
                        placeholderText: I18n.t("guide.keybindings.search_placeholder", "Поиск по комбинации или названию (например, Super + I, терминал, закрыть)...")
                        text: keybindingsTabRoot.searchQuery
                        onTextChanged: keybindingsTabRoot.searchQuery = text
                    }
                }
            }

            // Keybinding Add / Edit Panel (Collapsible)
            Rectangle {
                Layout.fillWidth: true
                visible: editorOpen
                implicitHeight: editorCol.implicitHeight + s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.6)
                border.width: 1
                border.color: Qt.alpha(ThemeBackend.mauve, 0.4)

                ColumnLayout {
                    id: editorCol
                    anchors.fill: parent
                    anchors.margins: s(14)
                    spacing: s(10)

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: isEditingStandard
                                ? I18n.t("guide.keybindings.edit_standard_title", "Изменить стандартную комбинацию") + " (" + newTitle + ")"
                                : (editingId !== ""
                                    ? I18n.t("guide.keybindings.edit_custom_title", "Редактировать комбинацию")
                                    : I18n.t("guide.keybindings.editor_title", "Добавить пользовательскую комбинацию (userprefs)"))
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: s(13)
                            font.bold: true
                            color: ThemeBackend.mauve
                        }

                        IconButton {
                            size: s(24)
                            cornerRadius: s(6)
                            buttonIcon: "󰅖"
                            iconFontSize: s(14)
                            accentColor: "transparent"
                            textColor: ThemeBackend.subtext0
                            onClicked: editorOpen = false
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: s(8)

                        Input {
                            Layout.preferredWidth: s(180)
                            implicitHeight: s(34)
                            cornerRadius: s(6)
                            baseColor: Qt.alpha(ThemeBackend.surface1, 0.6)
                            placeholderText: I18n.t("guide.keybindings.keys_hint", "Super + Alt + Z")
                            text: newKey
                            onTextChanged: newKey = text
                        }

                        Input {
                            Layout.fillWidth: true
                            visible: !isEditingStandard
                            implicitHeight: s(34)
                            cornerRadius: s(6)
                            baseColor: Qt.alpha(ThemeBackend.surface1, 0.6)
                            placeholderText: I18n.t("guide.keybindings.action_cmd", "Команда (напр. zen-browser)")
                            text: newExec
                            onTextChanged: newExec = text
                        }

                        Input {
                            Layout.preferredWidth: s(160)
                            visible: !isEditingStandard
                            implicitHeight: s(34)
                            cornerRadius: s(6)
                            baseColor: Qt.alpha(ThemeBackend.surface1, 0.6)
                            placeholderText: I18n.t("guide.keybindings.name", "Название (опционально)")
                            text: newTitle
                            onTextChanged: newTitle = text
                        }

                        ClickButton {
                            implicitHeight: s(34)
                            implicitWidth: s(100)
                            cornerRadius: s(6)
                            buttonText: I18n.t("guide.keybindings.save", "Сохранить")
                            textFontSize: s(11)
                            accentColor: ThemeBackend.mauve
                            textColor: ThemeBackend.crust
                            onClicked: saveKeybinding()
                        }
                    }
                }
            }

            // Category Filter Pills
            RowLayout {
                Layout.fillWidth: true
                spacing: s(6)

                Repeater {
                    model: [
                        { key: "all", label: I18n.t("guide.keybindings.cat_all", "Все") },
                        { key: "shell", label: I18n.t("guide.keybindings.cat_shell", "Оболочка") },
                        { key: "windows", label: I18n.t("guide.keybindings.cat_windows", "Окна") },
                        { key: "apps", label: I18n.t("guide.keybindings.cat_apps", "Приложения") },
                        { key: "media", label: I18n.t("guide.keybindings.cat_media", "Медиа") },
                        { key: "custom", label: I18n.t("guide.keybindings.cat_custom", "Свои") + " (" + customList.length + ")" }
                    ]
                    delegate: Rectangle {
                        implicitHeight: s(28)
                        implicitWidth: catLabel.implicitWidth + s(20)
                        radius: s(14)
                        color: keybindingsTabRoot.currentCategory === modelData.key
                            ? ThemeBackend.mauve
                            : Qt.alpha(ThemeBackend.surface1, 0.4)

                        Text {
                            id: catLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: s(11)
                            font.bold: keybindingsTabRoot.currentCategory === modelData.key
                            color: keybindingsTabRoot.currentCategory === modelData.key
                                ? ThemeBackend.crust
                                : ThemeBackend.subtext0
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: keybindingsTabRoot.currentCategory = modelData.key
                        }
                    }
                }
            }

            // Keybindings Cards List
            ColumnLayout {
                Layout.fillWidth: true
                spacing: s(8)

                Repeater {
                    model: keybindingsTabRoot.allItems
                    delegate: Rectangle {
                        id: itemCard
                        property var cardKeys: modelData.keys || []
                        Layout.fillWidth: true
                        implicitHeight: itemRow.implicitHeight + s(20)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.surface0, 0.35)

                        GlassFill {
                            anchors.fill: parent
                            radius: parent.radius
                            tintColor: Qt.alpha(ThemeBackend.surface0, 0.35)
                            tintAmount: 0.15
                        }

                        RowLayout {
                            id: itemRow
                            anchors.fill: parent
                            anchors.leftMargin: s(14)
                            anchors.rightMargin: s(14)
                            anchors.topMargin: s(10)
                            anchors.bottomMargin: s(10)
                            spacing: s(12)

                            // 1. ОПИСАНИЕ В НАЧАЛЕ (Слева): Название и описание
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: s(2)

                                RowLayout {
                                    spacing: s(6)

                                    Text {
                                        text: modelData.title || ""
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: s(13)
                                        font.bold: true
                                        color: ThemeBackend.text
                                        elide: Text.ElideRight
                                    }

                                    // Overridden Badge
                                    Rectangle {
                                        visible: !!modelData.isOverridden
                                        implicitHeight: s(18)
                                        implicitWidth: overriddenBadgeText.implicitWidth + s(10)
                                        radius: s(9)
                                        color: Qt.alpha(ThemeBackend.peach, 0.25)

                                        Text {
                                            id: overriddenBadgeText
                                            anchors.centerIn: parent
                                            text: I18n.t("guide.keybindings.overridden", "Изменен")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: s(9)
                                            font.bold: true
                                            color: ThemeBackend.peach
                                        }
                                    }

                                    // Custom Badge
                                    Rectangle {
                                        visible: !!modelData.isCustom
                                        implicitHeight: s(18)
                                        implicitWidth: customBadgeText.implicitWidth + s(10)
                                        radius: s(9)
                                        color: Qt.alpha(ThemeBackend.mauve, 0.25)

                                        Text {
                                            id: customBadgeText
                                            anchors.centerIn: parent
                                            text: I18n.t("guide.keybindings.custom_badge", "Свой")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: s(9)
                                            font.bold: true
                                            color: ThemeBackend.mauve
                                        }
                                    }
                                }

                                Text {
                                    text: modelData.desc || ""
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(10)
                                    color: ThemeBackend.subtext0
                                    elide: Text.ElideRight
                                }
                            }

                            // 2. КЕЙБИНД В КОНЦЕ (Справа): Клавиши комбинации
                            RowLayout {
                                spacing: s(4)
                                Repeater {
                                    model: itemCard.cardKeys
                                    delegate: RowLayout {
                                        spacing: s(4)
                                        Rectangle {
                                            implicitHeight: s(26)
                                            implicitWidth: Math.max(s(28), keyText.implicitWidth + s(14))
                                            radius: s(6)
                                            color: modelData.isOverridden ? Qt.alpha(ThemeBackend.peach, 0.2) : Qt.alpha(ThemeBackend.surface2, 0.6)
                                            border.width: 1
                                            border.color: modelData.isOverridden ? Qt.alpha(ThemeBackend.peach, 0.5) : Qt.alpha(ThemeBackend.mauve, 0.3)

                                            Text {
                                                id: keyText
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: s(11)
                                                font.bold: true
                                                color: ThemeBackend.text
                                            }
                                        }

                                        Text {
                                            visible: index < (itemCard.cardKeys.length - 1)
                                            text: "+"
                                            font.pixelSize: s(11)
                                            font.bold: true
                                            color: ThemeBackend.subtext0
                                        }
                                    }
                                }
                            }

                            // 3. КНОПКИ ДЕЙСТВИЙ: Сброс, Изменить, Удалить
                            RowLayout {
                                spacing: s(6)

                                // Reset to default button (for overridden standard bindings)
                                IconButton {
                                    visible: !!modelData.isOverridden
                                    size: s(28)
                                    cornerRadius: s(6)
                                    buttonIcon: "󰁯"
                                    iconFontSize: s(14)
                                    accentColor: Qt.alpha(ThemeBackend.peach, 0.2)
                                    textColor: ThemeBackend.peach
                                    onClicked: resetStandardKeybinding(modelData.id)
                                }

                                // Edit button for ALL bindings (standard and custom)
                                IconButton {
                                    size: s(28)
                                    cornerRadius: s(6)
                                    buttonIcon: "󰏫"
                                    iconFontSize: s(14)
                                    accentColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                    textColor: ThemeBackend.text
                                    onClicked: startEditing(modelData)
                                }

                                // Custom delete button
                                DeleteButton {
                                    visible: !!modelData.isCustom
                                    size: s(28)
                                    cornerRadius: s(6)
                                    onClicked: deleteCustomKeybinding(modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
