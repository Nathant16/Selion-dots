pragma Singleton
import QtQuick

QtObject {
    id: root

    property var bars: ({})
    property var docks: ({})
    property bool isLocked: false

    function register(kind, screenName, window) {
        if (!screenName || !window) return;
        root[kind][screenName] = window;
    }

    function unregister(kind, screenName, window) {
        if (root[kind][screenName] === window) delete root[kind][screenName];
    }
}
