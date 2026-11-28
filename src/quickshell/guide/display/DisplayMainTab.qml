import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"

DisplayMainState {
    id: displayTabRoot

    GuideScrollView {
        id: displayScrollView
        rootObj: displayTabRoot.rootObj
        spacing: rootObj.s(12)
        interactive: !stageCanvas.isDraggingLayout

        // 2D Monitor Stage & Layout Overview
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: rootObj.s(displayTabRoot.monitorsList.length > 1 ? 230 : 180)
            Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
            radius: ThemeBackend.borderRadius
            color: stageGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, 0.4)
            clip: true

            GlassFill {
                id: stageGlass
                anchors.fill: parent
                radius: parent.radius
                tintColor: Qt.alpha(ThemeBackend.surface0, 0.4)
                tintAmount: 0.25
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: rootObj.s(12)
                spacing: rootObj.s(8)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: rootObj.s(8)

                    Text {
                        text: I18n.t("guide.display.layout_stage", "2D Monitor Layout")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(13)
                        font.bold: true
                        color: ThemeBackend.text
                    }

                    Text {
                        visible: displayTabRoot.monitorsList.length > 1
                        text: "•  " + I18n.t("guide.display.layout_drag_hint", "Drag displays to arrange")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.subtext0
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Item {
                        visible: displayTabRoot.monitorsList.length <= 1
                        Layout.fillWidth: true
                    }

                    Text {
                        text: displayTabRoot.monitorsList.length + " " + I18n.t("guide.display.monitors_detected", "monitor(s)")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.subtext0
                    }
                }

                // Proportional Interactive 2D Canvas Stage
                Rectangle {
                    id: stageCanvas
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: rootObj.s(8)
                    color: Qt.alpha(ThemeBackend.crust, 0.4)
                    border.width: 1
                    border.color: Qt.alpha(ThemeBackend.surface1, 0.5)
                    clip: true

                    readonly property bool canDrag: displayTabRoot.monitorsList.length > 1
                    property bool isDraggingLayout: false
                    property string draggedName: ""
                    property string hoveredName: ""
                    property int dragIdx: -1
                    property var draftBoxes: []
                    property var frozenViewport: ({ scale: 0.08, centerX: 960, centerY: 540 })
                    property var snapGuides: ({ hasX: false, gx: 0, hasY: false, gy: 0 })

                    signal tileDropped(string name)

                    readonly property var liveBoxes: {
                        let out = [];
                        let list = displayTabRoot.monitorsList || [];
                        for (let i = 0; i < list.length; i++) {
                            if (list[i] && list[i].name) {
                                out.push(displayTabRoot.logicalBoxFor(list[i]));
                            }
                        }
                        return out;
                    }

                    readonly property var displayBoxes: isDraggingLayout ? draftBoxes : liveBoxes

                    function computeViewport(boxes) {
                        let padX = rootObj.s(22);
                        let padY = rootObj.s(16);
                        let availW = Math.max(40, stageCanvas.width - padX * 2);
                        let availH = Math.max(40, stageCanvas.height - padY * 2);
                        if (!boxes || boxes.length === 0) {
                            return { scale: 0.08, centerX: 960, centerY: 540 };
                        }
                        let minX = boxes[0].x;
                        let minY = boxes[0].y;
                        let maxX = boxes[0].x + boxes[0].logW;
                        let maxY = boxes[0].y + boxes[0].logH;
                        for (let i = 1; i < boxes.length; i++) {
                            let b = boxes[i];
                            if (b.x < minX) minX = b.x;
                            if (b.y < minY) minY = b.y;
                            if (b.x + b.logW > maxX) maxX = b.x + b.logW;
                            if (b.y + b.logH > maxY) maxY = b.y + b.logH;
                        }
                        let spanW = Math.max(1, maxX - minX);
                        let spanH = Math.max(1, maxY - minY);
                        let maxCap = boxes.length === 1 ? rootObj.s(0.088) : rootObj.s(0.115);
                        let fitScale = Math.min(availW / spanW, availH / spanH, maxCap);
                        return {
                            scale: Math.max(0.01, fitScale),
                            centerX: minX + spanW / 2,
                            centerY: minY + spanH / 2
                        };
                    }

                    readonly property var activeViewport: isDraggingLayout ? frozenViewport : computeViewport(liveBoxes)

                    function snapPosition(dragIdx, candX, candY, vpScale) {
                        let boxes = stageCanvas.draftBoxes;
                        let me = boxes[dragIdx];
                        if (!me) return { x: candX, y: candY, hasX: false, gx: 0, hasY: false, gy: 0 };

                        let snapTol = Math.max(10, Math.min(48, Math.round(rootObj.s(4.5) / Math.max(0.02, vpScale))));
                        let bestX = Math.round(candX);
                        let bestY = Math.round(candY);
                        let bestDistX = snapTol + 1;
                        let bestDistY = snapTol + 1;
                        let guideX = 0;
                        let guideY = 0;
                        let hasX = false;
                        let hasY = false;

                        for (let i = 0; i < boxes.length; i++) {
                            if (i === dragIdx) continue;
                            let ot = boxes[i];

                            let nearYBand = candY < (ot.y + ot.logH + snapTol) && (candY + me.logH) > (ot.y - snapTol);
                            let nearXBand = candX < (ot.x + ot.logW + snapTol) && (candX + me.logW) > (ot.x - snapTol);
                            let clearAboveOrBelow = (candY + me.logH) <= (ot.y + snapTol) || candY >= (ot.y + ot.logH - snapTol);
                            let clearLeftOrRight = (candX + me.logW) <= (ot.x + snapTol) || candX >= (ot.x + ot.logW - snapTol);

                            let xCands = [];
                            if (nearYBand) {
                                xCands.push(
                                    { x: ot.x + ot.logW, g: ot.x + ot.logW },
                                    { x: ot.x - me.logW, g: ot.x }
                                );
                            }
                            if (clearAboveOrBelow) {
                                xCands.push(
                                    { x: ot.x, g: ot.x },
                                    { x: ot.x + ot.logW - me.logW, g: ot.x + ot.logW },
                                    { x: Math.round(ot.x + (ot.logW - me.logW) / 2), g: ot.x + ot.logW / 2 }
                                );
                            }
                            for (let k = 0; k < xCands.length; k++) {
                                let d = Math.abs(candX - xCands[k].x);
                                if (d < bestDistX) {
                                    bestDistX = d;
                                    bestX = Math.round(xCands[k].x);
                                    guideX = xCands[k].g;
                                    hasX = true;
                                }
                            }

                            let yCands = [];
                            if (nearXBand) {
                                yCands.push(
                                    { y: ot.y + ot.logH, g: ot.y + ot.logH },
                                    { y: ot.y - me.logH, g: ot.y }
                                );
                            }
                            if (clearLeftOrRight) {
                                yCands.push(
                                    { y: ot.y, g: ot.y },
                                    { y: ot.y + ot.logH - me.logH, g: ot.y + ot.logH },
                                    { y: Math.round(ot.y + (ot.logH - me.logH) / 2), g: ot.y + ot.logH / 2 }
                                );
                            }
                            for (let k = 0; k < yCands.length; k++) {
                                let d = Math.abs(candY - yCands[k].y);
                                if (d < bestDistY) {
                                    bestDistY = d;
                                    bestY = Math.round(yCands[k].y);
                                    guideY = yCands[k].g;
                                    hasY = true;
                                }
                            }
                        }
                        return { x: bestX, y: bestY, hasX: hasX, gx: guideX, hasY: hasY, gy: guideY };
                    }

                    function tileIndexAt(sx, sy) {
                        let boxes = stageCanvas.displayBoxes;
                        if (!boxes || boxes.length === 0) return -1;
                        let vp = stageCanvas.activeViewport;
                        let bestIdx = -1;
                        let bestScore = -1;
                        for (let i = 0; i < boxes.length; i++) {
                            let b = boxes[i];
                            let rx = stageCanvas.width / 2 + (b.x - vp.centerX) * vp.scale;
                            let ry = stageCanvas.height / 2 + (b.y - vp.centerY) * vp.scale;
                            let rw = Math.max(rootObj.s(28), b.logW * vp.scale);
                            let rh = Math.max(rootObj.s(24), b.logH * vp.scale);
                            if (sx >= rx && sx <= (rx + rw) && sy >= ry && sy <= (ry + rh)) {
                                let score = (b.active ? 100 : 0) + i;
                                if (score >= bestScore) {
                                    bestScore = score;
                                    bestIdx = i;
                                }
                            }
                        }
                        return bestIdx;
                    }

                    function rectsOverlap(a, b) {
                        return a.x < (b.x + b.logW) && (a.x + a.logW) > b.x
                            && a.y < (b.y + b.logH) && (a.y + a.logH) > b.y;
                    }

                    function finalizeAndCommit(dragIdx) {
                        let boxes = stageCanvas.draftBoxes.map(b => Object.assign({}, b));
                        let me = boxes[dragIdx];
                        if (!me) return;

                        // Resolve any overlapping placement onto the nearest non-overlapping side
                        for (let pass = 0; pass < boxes.length * 2; pass++) {
                            let hit = null;
                            for (let i = 0; i < boxes.length; i++) {
                                if (i === dragIdx) continue;
                                if (rectsOverlap(me, boxes[i])) {
                                    hit = boxes[i];
                                    break;
                                }
                            }
                            if (!hit) break;
                            let pushes = [
                                { dx: (hit.x + hit.logW) - me.x, dy: 0 },
                                { dx: (hit.x - me.logW) - me.x, dy: 0 },
                                { dx: 0, dy: (hit.y + hit.logH) - me.y },
                                { dx: 0, dy: (hit.y - me.logH) - me.y }
                            ];
                            pushes.sort((p, q) => (Math.abs(p.dx) + Math.abs(p.dy)) - (Math.abs(q.dx) + Math.abs(q.dy)));
                            me.x = Math.round(me.x + pushes[0].dx);
                            me.y = Math.round(me.y + pushes[0].dy);
                        }

                        // Normalize top-left origin of bounding box to (0, 0)
                        let minX = boxes[0].x;
                        let minY = boxes[0].y;
                        for (let k = 1; k < boxes.length; k++) {
                            if (boxes[k].x < minX) minX = boxes[k].x;
                            if (boxes[k].y < minY) minY = boxes[k].y;
                        }
                        let layoutItems = [];
                        for (let j = 0; j < boxes.length; j++) {
                            layoutItems.push({
                                name: boxes[j].name,
                                x: Math.round(boxes[j].x - minX),
                                y: Math.round(boxes[j].y - minY)
                            });
                        }

                        let droppedName = me.name;
                        displayTabRoot.applyMonitorLayout(layoutItems);
                        stageCanvas.isDraggingLayout = false;
                        stageCanvas.draggedName = "";
                        stageCanvas.dragIdx = -1;
                        stageCanvas.snapGuides = { hasX: false, gx: 0, hasY: false, gy: 0 };
                        stageCanvas.tileDropped(droppedName);
                    }

                    // Snap alignment guide lines
                    Rectangle {
                        opacity: (stageCanvas.isDraggingLayout && stageCanvas.snapGuides.hasX) ? 0.85 : 0.0
                        visible: opacity > 0.01
                        x: stageCanvas.width / 2 + (stageCanvas.snapGuides.gx - stageCanvas.activeViewport.centerX) * stageCanvas.activeViewport.scale
                        y: 0
                        width: 1
                        height: stageCanvas.height
                        color: ThemeBackend.mauve
                        z: 5
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on x { enabled: stageCanvas.isDraggingLayout; NumberAnimation { duration: 100; easing.type: Easing.OutQuint } }
                    }

                    Rectangle {
                        opacity: (stageCanvas.isDraggingLayout && stageCanvas.snapGuides.hasY) ? 0.85 : 0.0
                        visible: opacity > 0.01
                        x: 0
                        y: stageCanvas.height / 2 + (stageCanvas.snapGuides.gy - stageCanvas.activeViewport.centerY) * stageCanvas.activeViewport.scale
                        width: stageCanvas.width
                        height: 1
                        color: ThemeBackend.mauve
                        z: 5
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on y { enabled: stageCanvas.isDraggingLayout; NumberAnimation { duration: 100; easing.type: Easing.OutQuint } }
                    }

                    Repeater {
                        model: stageCanvas.displayBoxes.length

                        delegate: Rectangle {
                            id: monitorTile
                            required property int index
                            readonly property var box: stageCanvas.displayBoxes[index] || ({ name: "", x: 0, y: 0, logW: 1920, logH: 1080, scale: 1.0, active: true, dimensions: "1920x1080" })
                            readonly property bool isDragged: stageCanvas.isDraggingLayout && stageCanvas.draggedName === box.name
                            readonly property bool isHovered: !stageCanvas.isDraggingLayout && stageDragArea.containsMouse && stageCanvas.hoveredName === box.name && stageCanvas.canDrag
                            readonly property bool isPressed: isDragged || (!stageCanvas.isDraggingLayout && stageDragArea.pressed && stageCanvas.hoveredName === box.name && stageCanvas.canDrag)
                            readonly property real vpScale: stageCanvas.activeViewport.scale
                            readonly property color grayFrameBase: Qt.tint(ThemeBackend.overlay0, Qt.rgba(0.52, 0.53, 0.56, 0.45))

                            property real popScale: 1.0
                            property real flashOpacity: 0.0

                            Connections {
                                target: stageCanvas
                                function onTileDropped(name) {
                                    if (name === monitorTile.box.name) {
                                        monitorTile.flashOpacity = 0.16;
                                        tileFlashAnim.restart();
                                        tileDropPopAnim.restart();
                                    }
                                }
                            }

                            x: stageCanvas.width / 2 + (box.x - stageCanvas.activeViewport.centerX) * vpScale
                            y: stageCanvas.height / 2 + (box.y - stageCanvas.activeViewport.centerY) * vpScale
                            width: Math.max(rootObj.s(28), box.logW * vpScale)
                            height: Math.max(rootObj.s(24), box.logH * vpScale)
                            z: isDragged ? 10 : (box.active ? 2 : 1)

                            scale: (isDragged
                                ? 1.025
                                : (isPressed ? 0.975 : (isHovered ? 1.015 : 1.0))) * monitorTile.popScale

                            radius: rootObj.s(6)
                            opacity: box.active ? 1.0 : 0.72
                            readonly property color tileTint: isDragged
                                ? Qt.alpha(ThemeBackend.surface1, box.active ? 0.85 : 0.48)
                                : (box.active ? Qt.alpha(ThemeBackend.surface1, isHovered ? 0.78 : 0.68) : Qt.alpha(ThemeBackend.surface0, 0.34))
                            color: tileGlass.active ? "transparent" : tileTint
                            border.width: isDragged ? 2.5 : (box.active && isHovered ? 2.0 : 1.5)
                            border.color: !box.active
                                ? (isDragged ? Qt.lighter(grayFrameBase, 1.2) : grayFrameBase)
                                : (isDragged || isHovered ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.mauve, 0.82))

                            Behavior on x { enabled: !stageCanvas.isDraggingLayout; NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                            Behavior on y { enabled: !stageCanvas.isDraggingLayout; NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                            Behavior on width { enabled: !stageCanvas.isDraggingLayout; NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                            Behavior on height { enabled: !stageCanvas.isDraggingLayout; NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }
                            Behavior on border.width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            GlassFill {
                                id: tileGlass
                                anchors.fill: parent
                                radius: parent.radius
                                tintColor: monitorTile.tileTint
                                tintAmount: monitorTile.box.active ? (monitorTile.isDragged ? 0.42 : (monitorTile.isHovered ? 0.34 : 0.26)) : 0.16
                                press: monitorTile.isPressed ? 0.9 : (monitorTile.isHovered ? 0.25 : 0.0)
                                pulse: Math.min(1, monitorTile.flashOpacity * 2.5)
                                Behavior on press { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on tintAmount { NumberAnimation { duration: 150 } }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "#ffffff"
                                opacity: monitorTile.flashOpacity
                                visible: !tileGlass.active && opacity > 0.001
                            }

                            NumberAnimation {
                                id: tileFlashAnim
                                target: monitorTile
                                property: "flashOpacity"
                                to: 0.0
                                duration: 400
                                easing.type: Easing.OutExpo
                            }

                            SequentialAnimation {
                                id: tileDropPopAnim
                                NumberAnimation { target: monitorTile; property: "popScale"; to: 1.02; duration: 100; easing.type: Easing.OutQuad }
                                NumberAnimation { target: monitorTile; property: "popScale"; to: 1.0; duration: 400; easing.type: Easing.OutQuint }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                width: Math.max(10, parent.width - rootObj.s(10))
                                spacing: monitorTile.height < rootObj.s(66) ? rootObj.s(1) : rootObj.s(2)

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: parent.width
                                    text: monitorTile.box.name
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: monitorTile.height < rootObj.s(54) ? rootObj.s(9) : rootObj.s(11)
                                    font.bold: true
                                    color: monitorTile.box.active ? ThemeBackend.text : ThemeBackend.subtext0
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: monitorTile.height >= rootObj.s(38) && monitorTile.width >= rootObj.s(74)
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: parent.width
                                    text: monitorTile.box.dimensions + " • " + Math.round(monitorTile.box.scale * 100) + "%"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: monitorTile.height < rootObj.s(56) ? rootObj.s(8) : rootObj.s(9)
                                    color: monitorTile.box.active ? ThemeBackend.subtext0 : ThemeBackend.overlay1
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: displayTabRoot.monitorsList.length > 1 && monitorTile.height >= rootObj.s(50) && monitorTile.width >= rootObj.s(60)
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: parent.width
                                    text: Math.round(monitorTile.box.x) + ", " + Math.round(monitorTile.box.y)
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: monitorTile.height < rootObj.s(60) ? rootObj.s(7.5) : rootObj.s(8.5)
                                    color: (monitorTile.isDragged && monitorTile.box.active) ? ThemeBackend.mauve : (monitorTile.box.active ? ThemeBackend.subtext0 : ThemeBackend.overlay1)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    elide: Text.ElideRight
                                }
                            }

                        }
                    }

                    // Fixed canvas-space MouseArea prevents scale/position animation feedback loops during drag
                    MouseArea {
                        id: stageDragArea
                        anchors.fill: parent
                        z: 20
                        enabled: stageCanvas.canDrag
                        hoverEnabled: stageCanvas.canDrag
                        preventStealing: true
                        cursorShape: !stageCanvas.canDrag ? Qt.ArrowCursor : (stageCanvas.isDraggingLayout ? Qt.ClosedHandCursor : (stageCanvas.hoveredName !== "" ? Qt.OpenHandCursor : Qt.ArrowCursor))

                        property point pressStagePos: Qt.point(0, 0)
                        property real origX: 0
                        property real origY: 0

                        onPressed: function(mouse) {
                            let idx = stageCanvas.tileIndexAt(mouse.x, mouse.y);
                            if (idx < 0 || idx >= stageCanvas.liveBoxes.length) return;
                            let boxesCopy = stageCanvas.liveBoxes.map(b => Object.assign({}, b));
                            let targetBox = boxesCopy[idx];
                            if (!targetBox) return;
                            pressStagePos = Qt.point(mouse.x, mouse.y);
                            origX = targetBox.x;
                            origY = targetBox.y;
                            stageCanvas.frozenViewport = stageCanvas.computeViewport(boxesCopy);
                            stageCanvas.draftBoxes = boxesCopy;
                            stageCanvas.dragIdx = idx;
                            stageCanvas.draggedName = targetBox.name;
                            stageCanvas.hoveredName = targetBox.name;
                            stageCanvas.snapGuides = { hasX: false, gx: 0, hasY: false, gy: 0 };
                            stageCanvas.isDraggingLayout = true;
                        }

                        onPositionChanged: function(mouse) {
                            if (!stageCanvas.isDraggingLayout) {
                                let idx = stageCanvas.tileIndexAt(mouse.x, mouse.y);
                                let boxes = stageCanvas.displayBoxes;
                                stageCanvas.hoveredName = (idx >= 0 && idx < boxes.length) ? boxes[idx].name : "";
                                return;
                            }
                            let dIdx = stageCanvas.dragIdx;
                            if (dIdx < 0 || dIdx >= stageCanvas.draftBoxes.length) return;
                            let vp = stageCanvas.frozenViewport;
                            let rawX = origX + (mouse.x - pressStagePos.x) / vp.scale;
                            let rawY = origY + (mouse.y - pressStagePos.y) / vp.scale;
                            let snapped = stageCanvas.snapPosition(dIdx, rawX, rawY, vp.scale);

                            let nextBoxes = stageCanvas.draftBoxes.slice();
                            let updated = Object.assign({}, nextBoxes[dIdx]);
                            updated.x = snapped.x;
                            updated.y = snapped.y;
                            nextBoxes[dIdx] = updated;
                            stageCanvas.draftBoxes = nextBoxes;
                            stageCanvas.snapGuides = {
                                hasX: snapped.hasX, gx: snapped.gx,
                                hasY: snapped.hasY, gy: snapped.gy
                            };
                        }

                        onReleased: function() {
                            if (!stageCanvas.isDraggingLayout || stageCanvas.dragIdx < 0) return;
                            stageCanvas.finalizeAndCommit(stageCanvas.dragIdx);
                        }

                        onExited: {
                            if (!stageCanvas.isDraggingLayout) {
                                stageCanvas.hoveredName = "";
                            }
                        }

                        onCanceled: function() {
                            stageCanvas.isDraggingLayout = false;
                            stageCanvas.draggedName = "";
                            stageCanvas.dragIdx = -1;
                            stageCanvas.snapGuides = { hasX: false, gx: 0, hasY: false, gy: 0 };
                        }
                    }
                }
            }
        }

        Repeater {
            model: displayTabRoot.monitorNames
            delegate: DisplayMonitorCard { tab: displayTabRoot }
        }
    }
}
