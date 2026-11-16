import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../singletons/system"
import "../singletons/theme"
import "../reusables"
import "../reusables/display"
import "../"

PanelWindow {
    id: mapWindow

    WlrLayershell.namespace: "drift-canvas-map"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Click-through when hidden, interactive across the card surface when shown
    Region { id: emptyRegion }
    mask: (mapCard.isShown && mapCard.opacity > 0.05) ? null : emptyRegion

    anchors {
        bottom: true
        right: true
    }

    margins {
        bottom: s(28)
        right: s(28)
    }

    function s(val) { return (typeof Scaler !== "undefined") ? Scaler.s(val) : val; }

    function formatAppName(rawAppId, rawTitle) {
        let app = String(rawAppId || "").trim();
        let title = String(rawTitle || "").trim();

        if (app !== "") {
            if (app.endsWith(".desktop")) app = app.slice(0, -8);

            // Strip reverse domain prefixes like org.gnome.Loupe -> Loupe
            if (app.indexOf(".") !== -1) {
                let parts = app.split(".");
                let last = parts[parts.length - 1];
                if (last && last.length > 1) {
                    app = last;
                }
            }

            let lower = app.toLowerCase();
            if (lower === "ski-file-manager" || lower === "ski") return "Ski";
            if (lower.startsWith("zen")) return "Zen";
            if (lower === "google-chrome" || lower === "chrome") return "Chrome";
            if (lower.startsWith("code")) return "Code";
            if (lower === "ayugram" || lower.indexOf("telegram") !== -1) return "Telegram";
            if (lower.indexOf("firefox") !== -1) return "Firefox";
            if (lower === "org.gnome.loupe" || lower === "loupe") return "Loupe";

            app = app.replace(/-file-manager$/i, "")
                     .replace(/-browser$/i, "")
                     .replace(/-desktop$/i, "")
                     .replace(/_desktop$/i, "");

            if (app.length > 0) {
                return app.charAt(0).toUpperCase() + app.slice(1);
            }
        }

        if (title !== "") {
            if (title.indexOf(" — ") !== -1) {
                let parts = title.split(" — ");
                return parts[parts.length - 1].trim();
            }
            if (title.indexOf(" - ") !== -1) {
                let parts = title.split(" - ");
                return parts[parts.length - 1].trim();
            }
            return title.length > 10 ? title.substring(0, 9) + "…" : title;
        }

        return "";
    }

    implicitWidth: mapCard.width
    implicitHeight: mapCard.height

    Item {
        id: mapCard

        readonly property real cardWidth: mapWindow.s(280)
        readonly property real cardHeight: mapWindow.s(185)

        width: cardWidth
        height: cardHeight

        property bool isShown: false
        property real ySlide: isShown ? 0 : mapWindow.s(12)

        opacity: isShown ? 1.0 : 0.0
        scale: isShown ? 1.0 : 0.92
        visible: opacity > 0.005

        transform: Translate { y: mapCard.ySlide }

        Behavior on opacity {
            NumberAnimation {
                duration: mapCard.isShown ? 180 : 380
                easing.type: mapCard.isShown ? Easing.OutQuint : Easing.InCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: mapCard.isShown ? 240 : 380
                easing.type: mapCard.isShown ? Easing.OutBack : Easing.InCubic
            }
        }

        Behavior on ySlide {
            NumberAnimation {
                duration: mapCard.isShown ? 220 : 380
                easing.type: mapCard.isShown ? Easing.OutQuint : Easing.InCubic
            }
        }

        // Hover handling: keep map visible while mouse is hovered over it
        HoverHandler {
            id: cardHoverHandler
            onHoveredChanged: {
                if (hovered) {
                    hideTimer.stop();
                } else if (!mapCard.isPinned && mapCard.isShown) {
                    hideTimer.restart();
                }
            }
        }

        property bool isPinned: {
            if (typeof Config !== "undefined" && typeof Config.getSetting === "function") {
                let s = Config.getSetting("driftwm", {});
                return Boolean(s && s.minimapPinned);
            }
            return false;
        }

        function togglePin() {
            let nextPinned = !isPinned;
            isPinned = nextPinned;
            if (typeof Config !== "undefined" && typeof Config.setSetting === "function") {
                let s = Config.getSetting("driftwm", {}) || {};
                s.minimapPinned = nextPinned;
                Config.setSetting("driftwm", s);
            }
            if (!nextPinned) {
                if (!cardHoverHandler.hovered) {
                    hideTimer.restart();
                }
            } else {
                isShown = true;
            }
        }

        function wakeUp() {
            isShown = true;
            if (!isPinned && !cardHoverHandler.hovered) {
                hideTimer.restart();
            }
            DriftState.refreshBookmarks();
            recalcBounds();
        }

        Timer {
            id: hideTimer
            interval: 1800
            repeat: false
            onTriggered: {
                if (!mapCard.isPinned && !cardHoverHandler.hovered) {
                    mapCard.isShown = false;
                }
            }
        }

        Connections {
            target: DriftState
            function onCameraMoved() {
                mapCard.wakeUp();
            }
            function onWindowsUpdated() {
                mapCard.recalcBounds();
            }
            function onBookmarksUpdated() {
                mapCard.recalcBounds();
            }
        }

        // --- Smooth World Bounds & Auto-Scaling ---
        property real targetMinX: 0
        property real targetMaxX: 2500
        property real targetMinY: -600
        property real targetMaxY: 600

        property real worldCenterX: (targetMinX + targetMaxX) / 2
        property real worldCenterY: (targetMinY + targetMaxY) / 2
        property real worldW: Math.max(2400, targetMaxX - targetMinX)
        property real worldH: Math.max(1500, targetMaxY - targetMinY)

        Behavior on worldCenterX { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on worldCenterY { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on worldW { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on worldH { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        function recalcBounds() {
            let cx = DriftState.cameraX;
            let cy = DriftState.cameraY;
            let z = Math.max(0.1, DriftState.zoom);
            let sw = DriftState.screenWidth || 1920;
            let sh = DriftState.screenHeight || 1080;

            let vw = sw / z;
            let vh = sh / z;

            let minX = cx - vw / 2;
            let maxX = cx + vw / 2;
            let minY = cy - vh / 2;
            let maxY = cy + vh / 2;

            // Include all active windows on canvas
            let wins = DriftState.windows;
            if (wins && wins.length) {
                for (let i = 0; i < wins.length; i++) {
                    let w = wins[i];
                    if (!w || !w.position || !w.size) continue;
                    let wx = Number(w.position[0]) || 0;
                    let wy = Number(w.position[1]) || 0;
                    let ww = Number(w.size[0]) || 800;
                    let wh = Number(w.size[1]) || 500;

                    minX = Math.min(minX, wx - ww / 2);
                    maxX = Math.max(maxX, wx + ww / 2);
                    minY = Math.min(minY, wy - wh / 2);
                    maxY = Math.max(maxY, wy + wh / 2);
                }
            }

            // Include active bookmark in bounds calculation
            let bms = DriftState.bookmarks;
            if (bms) {
                let curKey = String(DriftState.activeIndex + 1);
                if (bms[curKey] && Array.isArray(bms[curKey])) {
                    let bx = Number(bms[curKey][0]) || 0;
                    let by = Number(bms[curKey][1]) || 0;
                    minX = Math.min(minX, bx - 600);
                    maxX = Math.max(maxX, bx + 600);
                    minY = Math.min(minY, by - 400);
                    maxY = Math.max(maxY, by + 400);
                }
            }

            // Margin padding around bounds
            let padX = Math.max(450, vw * 0.16);
            let padY = Math.max(350, vh * 0.16);

            targetMinX = minX - padX;
            targetMaxX = maxX + padX;
            targetMinY = minY - padY;
            targetMaxY = maxY + padY;

            let tw = Math.max(2600, targetMaxX - targetMinX);
            let th = Math.max(1600, targetMaxY - targetMinY);

            worldW = tw;
            worldH = th;
            worldCenterX = (targetMinX + targetMaxX) / 2;
            worldCenterY = (targetMinY + targetMaxY) / 2;
        }

        // --- Card Frame (Styled in Rice Design System) ---
        Rectangle {
            id: cardBg
            anchors.fill: parent
            radius: Math.min(ThemeBackend.borderRadius, mapWindow.s(18))
            color: ThemeBackend.blurBackground
                ? Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
                : Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.88)
            border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.09)
            border.width: 1
            clip: true

            GlassFill {
                anchors.fill: parent
                radius: cardBg.radius
                allowed: Boolean(ThemeBackend.glassBlur)
                tintColor: ThemeBackend.surface0
                tintAmount: 0.18
                tintStrength: 1.0
            }

            // Inner Shadow/Glow Accent Border
            Rectangle {
                anchors.fill: parent
                radius: cardBg.radius
                color: "transparent"
                border.color: Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.14)
                border.width: 1
            }

            // Content Column
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: mapWindow.s(10)
                spacing: mapWindow.s(9)

                // Top Header Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: mapWindow.s(8)

                    // Windows counter on the left
                    RowLayout {
                        spacing: mapWindow.s(5)
                        Text {
                            text: "󰖲"
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: mapWindow.s(13)
                            color: ThemeBackend.subtext0
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            text: (DriftState.windows ? DriftState.windows.length : 0) + " windows"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: mapWindow.s(10)
                            font.bold: true
                            color: ThemeBackend.subtext0
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Pill Badge in Panel Style (like language switcher)
                    Rectangle {
                        height: mapWindow.s(26)
                        radius: Math.max(0, ThemeBackend.borderRadius - mapWindow.s(2))
                        color: Qt.lighter(ThemeBackend.surface0, 1.15)
                        border.color: Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.85)
                        border.width: 1
                        implicitWidth: badgeRow.implicitWidth + mapWindow.s(20)

                        RowLayout {
                            id: badgeRow
                            anchors.centerIn: parent
                            spacing: mapWindow.s(7)

                            // Bookmark item
                            RowLayout {
                                spacing: mapWindow.s(4)
                                Text {
                                    text: "󰃀"
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: mapWindow.s(12)
                                    color: ThemeBackend.primary
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    id: activeNumText
                                    text: String(DriftState.activeIndex + 1)
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: mapWindow.s(11)
                                    font.bold: true
                                    color: ThemeBackend.text
                                    verticalAlignment: Text.AlignVCenter

                                    onTextChanged: numAnim.restart()
                                    NumberAnimation on opacity {
                                        id: numAnim
                                        from: 0.2
                                        to: 1.0
                                        duration: 220
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }

                            // Divider
                            Rectangle {
                                width: 1
                                height: mapWindow.s(12)
                                color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.15)
                            }

                            // Zoom item with magnifying glass
                            RowLayout {
                                spacing: mapWindow.s(4)
                                Text {
                                    text: "󰍉"
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: mapWindow.s(12)
                                    color: ThemeBackend.subtext0
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    text: Math.round(DriftState.zoom * 100) + "%"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: mapWindow.s(11)
                                    font.bold: true
                                    color: ThemeBackend.text
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    // Pin / Lock Button (matching DockAppMenu style: 󰤰 when pinned, 󰤱 when unpinned)
                    Rectangle {
                        id: pinBtn
                        width: mapWindow.s(26)
                        height: mapWindow.s(26)
                        radius: Math.max(0, ThemeBackend.borderRadius - mapWindow.s(2))
                        color: mapCard.isPinned
                            ? ThemeBackend.primary
                            : (pinMa.containsMouse ? Qt.lighter(ThemeBackend.surface0, 1.25) : Qt.lighter(ThemeBackend.surface0, 1.15))
                        border.color: mapCard.isPinned
                            ? ThemeBackend.primary
                            : Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.85)
                        border.width: 1
                        z: 10

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: mapCard.isPinned ? "󰤰" : "󰤱"
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: mapWindow.s(13)
                            color: mapCard.isPinned
                                ? ThemeBackend.crust
                                : (pinMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: pinMa
                            anchors.fill: parent
                            anchors.margins: -mapWindow.s(2)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mapCard.togglePin()
                        }
                    }
                }

                // Canvas Map Visual Surface
                Rectangle {
                    id: canvasArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: mapWindow.s(10)
                    clip: true
                    color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.65)
                    border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.08)
                    border.width: 1

                    readonly property real mapScale: Math.min(
                        canvasArea.width / Math.max(100, mapCard.worldW),
                        canvasArea.height / Math.max(100, mapCard.worldH)
                    )

                    function toMapX(wx) {
                        return canvasArea.width / 2 + (wx - mapCard.worldCenterX) * mapScale;
                    }

                    function toMapY(wy) {
                        // wy is Cartesian Y-up -> flip to screen Y-down
                        return canvasArea.height / 2 - (wy - mapCard.worldCenterY) * mapScale;
                    }

                    function toWorldX(mx) {
                        return mapCard.worldCenterX + (mx - canvasArea.width / 2) / Math.max(0.0001, mapScale);
                    }

                    function toWorldY(my) {
                        // flip back from screen Y-down to Cartesian Y-up
                        return mapCard.worldCenterY - (my - canvasArea.height / 2) / Math.max(0.0001, mapScale);
                    }

                    // Background Axis Grid lines
                    Rectangle {
                        x: 0
                        y: canvasArea.toMapY(0)
                        width: canvasArea.width
                        height: 1
                        z: 1
                        color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.04)
                    }

                    Rectangle {
                        x: canvasArea.toMapX(0)
                        y: 0
                        width: 1
                        height: canvasArea.height
                        z: 1
                        color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.04)
                    }

                    // Interactive Panning & Wheel Zooming on the canvas
                    MouseArea {
                        id: canvasPanMa
                        anchors.fill: parent
                        z: 2
                        hoverEnabled: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        acceptedButtons: Qt.LeftButton

                        property real lastPanTime: 0
                        property int wheelAccum: 0

                        Timer {
                            id: wheelDebounce
                            interval: 70
                            repeat: false
                            onTriggered: canvasPanMa.wheelAccum = 0
                        }

                        function panTo(mx, my, force) {
                            let now = Date.now();
                            if (!force && now - lastPanTime < 28) return;
                            lastPanTime = now;
                            let wx = Math.round(canvasArea.toWorldX(mx));
                            let wy = Math.round(canvasArea.toWorldY(my));
                            DriftState.setCamera(wx, wy);
                        }

                        onPressed: (mouse) => {
                            panTo(mouse.x, mouse.y, true);
                        }

                        onPositionChanged: (mouse) => {
                            if (pressed) {
                                panTo(mouse.x, mouse.y, false);
                            }
                        }

                        onReleased: (mouse) => {
                            panTo(mouse.x, mouse.y, true);
                        }

                        onWheel: (wheel) => {
                            wheelAccum += wheel.angleDelta.y;
                            wheelDebounce.restart();
                            if (wheelAccum >= 60) {
                                wheelAccum = 0;
                                DriftState.zoomIn();
                            } else if (wheelAccum <= -60) {
                                wheelAccum = 0;
                                DriftState.zoomOut();
                            }
                        }
                    }

                    // Top Zone Ruler for Bookmarks 1..9 (pinned along top of canvas so they NEVER collide with windows)
                    Repeater {
                        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]
                        delegate: Rectangle {
                            id: topBmRuler
                            required property int modelData

                            readonly property var bmCoords: {
                                let rev = DriftState.bookmarksRevision;
                                let bms = DriftState.bookmarks;
                                if (bms && bms[String(modelData)]) {
                                    return bms[String(modelData)];
                                }
                                return [(modelData - 1) * 2500, 0];
                            }
                            readonly property real bx: Number(bmCoords[0]) || 0
                            readonly property bool isCurrent: (DriftState.activeIndex + 1) === modelData

                            x: canvasArea.toMapX(bx) - width / 2
                            y: mapWindow.s(3)
                            width: mapWindow.s(14)
                            height: mapWindow.s(11)
                            radius: mapWindow.s(2.5)
                            z: 4

                            visible: x >= -width && x <= canvasArea.width + width
                            scale: isCurrent ? 1.10 : 1.0

                            color: isCurrent
                                ? ThemeBackend.primary
                                : Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.70)
                            border.color: isCurrent
                                ? "#ffffff"
                                : Qt.rgba(ThemeBackend.surface2.r, ThemeBackend.surface2.g, ThemeBackend.surface2.b, 0.70)
                            border.width: 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: 320
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on border.color {
                                ColorAnimation {
                                    duration: 320
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.25
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: topBmRuler.modelData
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: mapWindow.s(7)
                                font.bold: true
                                color: topBmRuler.isCurrent ? ThemeBackend.crust : ThemeBackend.subtext0

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 280
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DriftState.focusWorkspace(topBmRuler.modelData - 1)
                            }
                        }
                    }

                    // Vertical Zone Dividers for Bookmarks (Clean canvas partitioning without number clutter)
                    Repeater {
                        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]
                        delegate: Rectangle {
                            required property int modelData
                            readonly property var bmCoords: {
                                let rev = DriftState.bookmarksRevision;
                                let bms = DriftState.bookmarks;
                                if (bms && bms[String(modelData)]) {
                                    return bms[String(modelData)];
                                }
                                return [(modelData - 1) * 2500, 0];
                            }
                            readonly property real bx: Number(bmCoords[0]) || 0
                            readonly property bool isCurrent: (DriftState.activeIndex + 1) === modelData

                            x: canvasArea.toMapX(bx)
                            y: 0
                            width: 1
                            height: canvasArea.height
                            z: 1
                            color: isCurrent
                                ? Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.22)
                                : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.04)

                            Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }

                    // Windows on the Canvas (High-opacity solid cards to eliminate overlapping collisions)
                    Repeater {
                        model: DriftState.windows
                        delegate: Rectangle {
                            id: winRect
                            required property var modelData

                            readonly property real ww: (modelData.size && modelData.size[0]) ? Number(modelData.size[0]) : 800
                            readonly property real wh: (modelData.size && modelData.size[1]) ? Number(modelData.size[1]) : 500
                            readonly property real wx: (modelData.position && modelData.position[0]) ? Number(modelData.position[0]) : 0
                            readonly property real wy: (modelData.position && modelData.position[1]) ? Number(modelData.position[1]) : 0
                            readonly property bool isFocused: !!modelData.is_focused
                            readonly property bool isSuspended: !!modelData.suspended

                            width: Math.max(mapWindow.s(6), ww * canvasArea.mapScale)
                            height: Math.max(mapWindow.s(5), wh * canvasArea.mapScale)
                            x: canvasArea.toMapX(wx) - width / 2
                            y: canvasArea.toMapY(wy) - height / 2
                            radius: Math.max(2, Math.min(5, mapWindow.s(4)))
                            clip: true

                            // Z-ordering: focused window ALWAYS in front, higher IDs above lower IDs
                            z: isFocused ? 30 : (10 + (modelData.id ? (modelData.id % 12) : 0))

                            // High-opacity solid fill prevents messy text collisions when windows overlap
                            color: {
                                if (isFocused) return Qt.lighter(ThemeBackend.surface1, 1.15);
                                if (isSuspended) return Qt.rgba(ThemeBackend.surface0.r, ThemeBackend.surface0.g, ThemeBackend.surface0.b, 0.88);
                                if (winMa.containsMouse) return Qt.lighter(ThemeBackend.surface0, 1.20);
                                return Qt.rgba(ThemeBackend.surface0.r, ThemeBackend.surface0.g, ThemeBackend.surface0.b, 0.95);
                            }

                            border.width: isFocused ? 1.5 : 1
                            border.color: {
                                if (isFocused) return ThemeBackend.primary;
                                if (isSuspended) return Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.20);
                                return Qt.rgba(ThemeBackend.surface2.r, ThemeBackend.surface2.g, ThemeBackend.surface2.b, 0.90);
                            }

                            // Dark drop shadow outline for crisp window depth separation
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -1
                                radius: parent.radius + 1
                                z: -1
                                color: "transparent"
                                border.color: Qt.rgba(0, 0, 0, 0.45)
                                border.width: 1
                            }

                            // Minimalist app label inside window
                            Text {
                                anchors.fill: parent
                                anchors.margins: mapWindow.s(2)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                visible: parent.width > mapWindow.s(16) && parent.height > mapWindow.s(8)
                                text: mapWindow.formatAppName(modelData.app_id, modelData.title)
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: Math.max(7, Math.min(9, parent.height * 0.45))
                                font.bold: isFocused
                                color: isFocused ? "#ffffff" : ThemeBackend.subtext1
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            MouseArea {
                                id: winMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        if (modelData.suspended) {
                                            DriftState.relaunchWindow(modelData.id);
                                        } else {
                                            DriftState.focusWindow(modelData.id);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --- User's Viewport (Camera Frustum / Viewfinder) ---
                    Rectangle {
                        id: viewportRect
                        z: 45

                        readonly property real zoomLevel: Math.max(0.1, DriftState.zoom)
                        readonly property real sw: DriftState.screenWidth || 1920
                        readonly property real sh: DriftState.screenHeight || 1080

                        readonly property real vw: (sw / zoomLevel) * canvasArea.mapScale
                        readonly property real vh: (sh / zoomLevel) * canvasArea.mapScale

                        width: Math.max(mapWindow.s(16), vw)
                        height: Math.max(mapWindow.s(10), vh)
                        x: canvasArea.toMapX(DriftState.cameraX) - width / 2
                        y: canvasArea.toMapY(DriftState.cameraY) - height / 2
                        radius: mapWindow.s(4)

                        color: Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.10)
                        border.color: ThemeBackend.primary
                        border.width: 1.5

                        // Glow border
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -1
                            radius: parent.radius + 1
                            color: "transparent"
                            border.color: Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.40)
                            border.width: 1
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        DriftState.subscribeMinimap();
        if (mapCard.isPinned) {
            mapCard.isShown = true;
        }
        mapCard.recalcBounds();
    }

    Component.onDestruction: {
        DriftState.unsubscribeMinimap();
    }
}
