pragma Singleton
import QtQuick
import QtQuick.Window
import Quickshell
import "../../"

Item {
    id: root
    visible: false

    property string screenName: Screen.name
    property real currentWidth: 1920.0
    property real currentHeight: 1080.0

    property real uiScale: {
        var general = Config.getSetting("general", null);
        var val = (general && general.uiScale !== undefined) ? Number(general.uiScale) : 1.0;
        if (isNaN(val) || val <= 0) return 1.0;
        return Math.max(0.5, Math.min(2.0, val));
    }

    property real baseScale: uiScale

    function s(val) {
        return val * root.uiScale;
    }
}
