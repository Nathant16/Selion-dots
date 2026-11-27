import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "../../"
import "../../lock/redactor"

GuideTab {
    id: displayLockscreenRoot
    subTabIndex: 2

    property var defaultLockscreenSettings: ({
        "fingerprintEnabled": true,
        "attemptLimitEnabled": false,
        "passwordMaxAttempts": 5,
        "fingerprintMaxAttempts": 5,
        "backgroundMode": "follow",
        "customBackground": "",
        "promptBackdropMode": "desktop"
    })

    property var lockscreenSettings: {
        if (typeof Config !== "undefined" && typeof Config.getSetting === "function") {
            return Config.getSetting("lockscreen", displayLockscreenRoot.defaultLockscreenSettings);
        }
        return displayLockscreenRoot.defaultLockscreenSettings;
    }

    property bool fingerprintSupported: SystemInfo.hasFingerprint
    property string currentBackgroundMode: lockscreenSettings.backgroundMode === "custom" ? "custom" : "follow"
    property string currentCustomBackground: lockscreenSettings.customBackground ? String(lockscreenSettings.customBackground) : ""
    property string currentPromptBackdropMode: lockscreenSettings.promptBackdropMode === "wallpaper" ? "wallpaper" : "desktop"
    readonly property string currentWallpaperPath: {
        Wallpaper.screenWallpaperPaths;
        return Wallpaper.getWallpaperPath("");
    }
    readonly property bool customBackgroundActive: displayLockscreenRoot.currentBackgroundMode === "custom" && displayLockscreenRoot.currentCustomBackground !== ""
    readonly property string effectiveBackgroundPath: displayLockscreenRoot.customBackgroundActive ? displayLockscreenRoot.currentCustomBackground : displayLockscreenRoot.currentWallpaperPath
    readonly property bool effectiveBackgroundIsVideo: displayLockscreenRoot.isVideoPath(displayLockscreenRoot.effectiveBackgroundPath)
    property bool currentFingerprintEnabled: lockscreenSettings.fingerprintEnabled !== false
    property bool currentAttemptLimitEnabled: lockscreenSettings.attemptLimitEnabled === true
    property int currentPasswordMaxAttempts: lockscreenSettings.passwordMaxAttempts !== undefined ? lockscreenSettings.passwordMaxAttempts : 5
    property int currentFingerprintMaxAttempts: lockscreenSettings.fingerprintMaxAttempts !== undefined ? lockscreenSettings.fingerprintMaxAttempts : 5

    Process {
        id: fingerprintProbe
        command: ["bash", "-c", "if command -v serpantinum-core >/dev/null 2>&1; then serpantinum-core system fingerprint; elif command -v fprintd-list >/dev/null 2>&1; then out=$(fprintd-list \"$USER\" 2>&1) || exit 1; ! printf '%s\\n' \"$out\" | grep -qiE 'No devices available|found 0 devices' && printf '%s\\n' \"$out\" | grep -qiE 'Device at /net/reactivated/Fprint/Device/|found [1-9][0-9]* devices|Fingerprints for user|has no fingers enrolled'; else exit 1; fi"]
        onExited: (exitCode) => {
            let ok = (exitCode === 0);
            displayLockscreenRoot.fingerprintSupported = ok;
            SystemInfo.hasFingerprint = ok;
        }
    }

    Component.onCompleted: fingerprintProbe.running = true

    function isVideoPath(path) {
        let lp = String(path || "").toLowerCase();
        return lp.endsWith(".mp4") || lp.endsWith(".mkv") || lp.endsWith(".mov") || lp.endsWith(".webm");
    }

    function setBackgroundMode(mode) {
        displayLockscreenRoot.currentBackgroundMode = mode;
        displayLockscreenRoot.updateLockscreenSetting("backgroundMode", mode);
    }

    function setPromptBackdropMode(mode) {
        displayLockscreenRoot.currentPromptBackdropMode = mode;
        displayLockscreenRoot.updateLockscreenSetting("promptBackdropMode", mode);
    }

    function setCustomBackground(path) {
        displayLockscreenRoot.currentCustomBackground = path;
        displayLockscreenRoot.updateLockscreenSetting("customBackground", path);
    }

    function openRedactor() {
        LockLayoutStore.openRedactor("");
        if (rootObj && typeof rootObj.closePopup === "function") {
            rootObj.closePopup();
        } else {
            let dir = (typeof Caching !== "undefined" && Caching.serpantinumDir) ? Caching.serpantinumDir : "";
            Quickshell.execDetached(["bash", dir ? (dir + "/scripts/qs_manager.sh") : "qs_manager.sh", "close"]);
        }
    }

    function updateLockscreenSetting(key, value) {
        let current = JSON.parse(JSON.stringify((typeof Config !== "undefined" && typeof Config.getSetting === "function") ? (Config.getSetting("lockscreen", defaultLockscreenSettings) || defaultLockscreenSettings) : defaultLockscreenSettings));
        current[key] = value;
        if (typeof Config !== "undefined" && typeof Config.setSetting === "function") {
            Config.setSetting("lockscreen", current);
        }
        displayLockscreenRoot.lockscreenSettings = current;
    }
}
