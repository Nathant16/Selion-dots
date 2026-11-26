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
        let bucket = root[kind];
        if (!bucket) return;
        if (screenName && bucket[screenName] === window) {
            delete bucket[screenName];
            return;
        }
        for (let key in bucket) {
            if (bucket[key] === window) delete bucket[key];
        }
    }
}
