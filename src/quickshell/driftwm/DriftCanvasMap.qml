import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../singletons/system"
import "../singletons/theme"
import "../reusables"
import "../"

PanelWindow {
    id: mapWindow

    WlrLayershell.namespace: "drift-canvas-map"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // 100% click-through: empty Region ensures all pointer events pass through to windows/canvas
    mask: Region {}

    anchors {
        bottom: true
        right: true
    }

    margins {
        bottom: s(28)
        right: s(28)
    }

    function s(val) { return (typeof Scaler !== "undefined") ? Scaler.s(val) : val; }

    implicitWidth: mapCard.width
    implicitHeight: mapCard.height

    Item {
        id: mapCard

        readonly property real cardWidth: mapWindow.s(270)
        readonly property real cardHeight: mapWindow.s(175)

        width: cardWidth
        height: cardHeight

        property bool isShown: false
        property real ySlide: isShown ? 0 : mapWindow.s(14)

        opacity: isShown ? 1.0 : 0.0
        scale: isShown ? 1.0 : 0.90
        visible: opacity > 0.005

        transform: Translate { y: mapCard.ySlide }

        Behavior on opacity {
            NumberAnimation {
                duration: mapCard.isShown ? 160 : 380
                easing.type: mapCard.isShown ? Easing.OutCubic : Easing.InCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: mapCard.isShown ? 220 : 380
                easing.type: mapCard.isShown ? Easing.OutBack : Easing.InCubic
            }
        }

        Behavior on ySlide {
            NumberAnimation {
                duration: mapCard.isShown ? 200 : 380
                easing.type: mapCard.isShown ? Easing.OutCubic : Easing.InCubic
            }
        }

        function wakeUp() {
            isShown = true;
            hideTimer.restart();
            recalcBounds();
        }

        Timer {
            id: hideTimer
            interval: 1600
            repeat: false
            onTriggered: {
                mapCard.isShown = false;
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

        Behavior on worldCenterX { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on worldCenterY { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on worldW { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on worldH { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

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
            let wins = DriftState.windows || [];
            for (let i = 0; i < wins.length; i++) {
                let w = wins[i];
                if (!w || !w.position || !w.size) continue;
                let wx = Number(w.position[0]) || 0;
                let wy = Number(w.position[1]) || 0;
                let ww = Number(w.size[0]) || 800;
                let wh = Number(w.size[1]) || 600;

                minX = Math.min(minX, wx - ww / 2);
                maxX = Math.max(maxX, wx + ww / 2);
                minY = Math.min(minY, wy - wh / 2);
                maxY = Math.max(maxY, wy + wh / 2);
            }

            // Include nearby active bookmark
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

        // --- Card Frame ---
        Rectangle {
            id: cardBg
            anchors.fill: parent
            radius: ThemeBackend.clampedBorderRadius > 0 ? Math.max(12, ThemeBackend.clampedBorderRadius) : mapWindow.s(16)
            color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, ThemeBackend.elementOpacity < 0.99 ? 0.72 : 0.84)
            border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.12)
            border.width: 1

            // Subtle outer ambient ring
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: parent.radius + 1
                color: "transparent"
                border.color: Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.15)
                border.width: 1
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: mapWindow.s(10)
                spacing: mapWindow.s(8)

                // Top Header Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: mapWindow.s(6)

                    // Mini compass radar dot
                    Rectangle {
                        width: mapWindow.s(8)
                        height: mapWindow.s(8)
                        radius: width / 2
                        color: ThemeBackend.primary

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + 4
                            height: parent.height + 4
                            radius: width / 2
                            color: "transparent"
                            border.color: Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.4)
                            border.width: 1
                        }
                    }

                    Text {
                        text: "DRIFT CANVAS"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: mapWindow.s(9)
                        font.bold: true
                        color: ThemeBackend.text
                        opacity: 0.85
                        Layout.fillWidth: true
                    }

                    // Bookmark & Zoom Pill Badge
                    Rectangle {
                        height: mapWindow.s(18)
                        radius: height / 2
                        color: Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.6)
                        border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.08)
                        border.width: 1
                        implicitWidth: badgeRow.implicitWidth + mapWindow.s(16)

                        RowLayout {
                            id: badgeRow
                            anchors.centerIn: parent
                            spacing: mapWindow.s(6)

                            Text {
                                text: "🔖 " + (DriftState.activeIndex + 1)
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: mapWindow.s(9)
                                font.bold: true
                                color: ThemeBackend.primary
                            }

                            Rectangle {
                                width: 1
                                height: mapWindow.s(10)
                                color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.15)
                            }

                            Text {
                                text: Math.round(DriftState.zoom * 100) + "%"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: mapWindow.s(9)
                                font.bold: true
                                color: ThemeBackend.text
                                opacity: 0.85
                            }
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
                    color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.65)
                    border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
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

                    // Background Axis Grid / Origin Crosshair
                    Rectangle {
                        x: 0
                        y: canvasArea.toMapY(0)
                        width: canvasArea.width
                        height: 1
                        color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
                    }

                    Rectangle {
                        x: canvasArea.toMapX(0)
                        y: 0
                        width: 1
                        height: canvasArea.height
                        color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
                    }

                    // Origin indicator dot (0, 0)
                    Rectangle {
                        x: canvasArea.toMapX(0) - width / 2
                        y: canvasArea.toMapY(0) - height / 2
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.25)
                    }

                    // Bookmarks Indicators
                    Repeater {
                        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]
                        delegate: Item {
                            id: bmItem
                            required property int modelData

                            readonly property var bmCoords: {
                                let bms = DriftState.bookmarks;
                                if (bms && bms[String(modelData)]) {
                                    return bms[String(modelData)];
                                }
                                return [(modelData - 1) * 2500, 0];
                            }
                            readonly property real bx: Number(bmCoords[0]) || 0
                            readonly property real by: Number(bmCoords[1]) || 0
                            readonly property bool isCurrent: (DriftState.activeIndex + 1) === modelData

                            x: canvasArea.toMapX(bx) - width / 2
                            y: canvasArea.toMapY(by) - height / 2
                            width: mapWindow.s(14)
                            height: mapWindow.s(14)

                            Rectangle {
                                anchors.centerIn: parent
                                width: isCurrent ? mapWindow.s(14) : mapWindow.s(10)
                                height: isCurrent ? mapWindow.s(14) : mapWindow.s(10)
                                radius: width / 2
                                color: isCurrent ? ThemeBackend.primary : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.08)
                                border.color: isCurrent ? "#ffffff" : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.15)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: isCurrent ? mapWindow.s(8) : mapWindow.s(6.5)
                                    font.bold: true
                                    color: isCurrent ? ThemeBackend.crust : ThemeBackend.subtext1
                                }
                            }
                        }
                    }

                    // Windows on the Canvas
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

                            width: Math.max(mapWindow.s(5), ww * canvasArea.mapScale)
                            height: Math.max(mapWindow.s(4), wh * canvasArea.mapScale)
                            x: canvasArea.toMapX(wx) - width / 2
                            y: canvasArea.toMapY(wy) - height / 2
                            radius: Math.max(2, Math.min(4, mapWindow.s(4)))

                            color: {
                                if (isFocused) return Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.42);
                                if (isSuspended) return Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.22);
                                return Qt.rgba(ThemeBackend.surface2.r, ThemeBackend.surface2.g, ThemeBackend.surface2.b, 0.60);
                            }

                            border.width: isFocused ? 1.5 : 1
                            border.color: {
                                if (isFocused) return ThemeBackend.primary;
                                if (isSuspended) return Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.18);
                                return Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.32);
                            }

                            // Minimalist app label inside window
                            Text {
                                anchors.centerIn: parent
                                visible: parent.width > mapWindow.s(26) && parent.height > mapWindow.s(12)
                                text: modelData.app_id ? modelData.app_id.substring(0, 6) : ""
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: Math.max(6, Math.min(8, parent.height * 0.45))
                                color: isFocused ? "#ffffff" : ThemeBackend.subtext0
                                opacity: 0.85
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }

                    // --- User's Viewport (Camera Frustum / "Где сейчас дисплей") ---
                    Rectangle {
                        id: viewportRect

                        readonly property real zoomLevel: Math.max(0.1, DriftState.zoom)
                        readonly property real sw: DriftState.screenWidth || 1920
                        readonly property real sh: DriftState.screenHeight || 1080

                        readonly property real vw: (sw / zoomLevel) * canvasArea.mapScale
                        readonly property real vh: (sh / zoomLevel) * canvasArea.mapScale

                        width: Math.max(mapWindow.s(14), vw)
                        height: Math.max(mapWindow.s(9), vh)
                        x: canvasArea.toMapX(DriftState.cameraX) - width / 2
                        y: canvasArea.toMapY(DriftState.cameraY) - height / 2
                        radius: mapWindow.s(4)

                        color: Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.16)
                        border.color: ThemeBackend.primary
                        border.width: 1.5

                        // Glow border
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -1
                            radius: parent.radius + 1
                            color: "transparent"
                            border.color: Qt.rgba(ThemeBackend.primary.r, ThemeBackend.primary.g, ThemeBackend.primary.b, 0.45)
                            border.width: 1
                        }

                        // Center reticle dot
                        Rectangle {
                            anchors.centerIn: parent
                            width: 3
                            height: 3
                            radius: 1.5
                            color: ThemeBackend.primary
                        }

                        // Tag "DISPLAY" on viewport
                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.top
                            anchors.bottomMargin: 2
                            visible: viewportRect.width > mapWindow.s(32)
                            height: mapWindow.s(11)
                            radius: 2
                            color: ThemeBackend.primary
                            implicitWidth: tagText.implicitWidth + 6

                            Text {
                                id: tagText
                                anchors.centerIn: parent
                                text: "DISPLAY"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: mapWindow.s(6.5)
                                font.bold: true
                                color: ThemeBackend.crust
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        DriftState.subscribeMinimap();
        mapCard.recalcBounds();
    }

    Component.onDestruction: {
        DriftState.unsubscribeMinimap();
    }
}
