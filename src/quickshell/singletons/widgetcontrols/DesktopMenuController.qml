pragma Singleton
import QtQuick

Item {
    id: controller

    signal menuTriggered()

    property bool isVisible: false
    property real targetX: 0
    property real targetY: 0
    property var screen: null
    property string mode: "desktop"
    property string targetWidgetId: ""
    property real menuOriginX: 0.5
    property real menuOriginY: 0.5
    property bool isMenuShuffle: false

    function openAt(scr, posX, posY, menuMode, widgetId) {
        controller.screen = scr !== undefined ? scr : null;
        controller.targetX = (typeof posX === "number" && !isNaN(posX)) ? posX : 0;
        controller.targetY = (typeof posY === "number" && !isNaN(posY)) ? posY : 0;
        controller.mode = menuMode !== undefined ? menuMode : "desktop";
        controller.targetWidgetId = widgetId !== undefined ? String(widgetId) : "";
        controller.isVisible = true;
        controller.menuTriggered();
    }

    function show(scr, posX, posY, menuMode, widgetId) {
        openAt(scr, posX, posY, menuMode, widgetId);
    }

    function hide() {
        controller.isVisible = false;
    }

    function toggle(scr, posX, posY, menuMode, widgetId) {
        let m = menuMode !== undefined ? menuMode : "desktop";
        let wId = widgetId !== undefined ? String(widgetId) : "";
        let px = (typeof posX === "number" && !isNaN(posX)) ? posX : 0;
        let py = (typeof posY === "number" && !isNaN(posY)) ? posY : 0;
        let sName = (scr && scr.name) ? scr.name : "";
        let curSName = (controller.screen && controller.screen.name) ? controller.screen.name : "";

        if (controller.isVisible) {
            let sameScreen = (!sName || !curSName || sName === curSName);
            let dx = Math.abs(controller.targetX - px);
            let dy = Math.abs(controller.targetY - py);
            let isSamePos = sameScreen && (dx < 10 && dy < 10);

            if (m === "widget") {
                // Widget logic: hide if clicked exact same spot, otherwise fall through to move/reopen
                if (controller.mode === "widget" && controller.targetWidgetId === wId && isSamePos) {
                    controller.hide();
                    return;
                }
            } else if (m === "desktop") {
                // Desktop logic: hide whenever clicked on wallpaper again while in desktop mode
                if (controller.mode === "desktop") {
                    controller.hide();
                    return;
                }
            }
        }

        openAt(scr, px, py, m, wId);
    }
}
