pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property string detectedName: {
        const desktop = (typeof SystemInfo !== "undefined" && SystemInfo.desktopEnv) ? SystemInfo.desktopEnv.toLowerCase() : "";
        if (Quickshell.env("DRIFTWM_SOCKET") || desktop.indexOf("drift") !== -1) return "driftwm";
        if (Quickshell.env("NIRI_SOCKET") || desktop.indexOf("niri") !== -1) return "niri";
        if (Quickshell.env("MANGO_INSTANCE_SIGNATURE") || desktop.indexOf("mango") !== -1) return "mango";
        if (Quickshell.env("SWAYSOCK") || desktop.indexOf("sway") !== -1) return "sway";
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || desktop.indexOf("hyprland") !== -1) return "hyprland";
        return "unknown";
    }

    readonly property string name: detectedName

    Process {
        id: compDetector
        running: root.detectedName === "unknown"
        command: ["bash", "-c", "
            uid=$(id -u)
            rdir=\"${XDG_RUNTIME_DIR:-/run/user/$uid}\"
            if [ -n \"$DRIFTWM_SOCKET\" ] || [ -d \"$rdir/driftwm\" ] || pgrep -x driftwm >/dev/null 2>&1; then echo driftwm; exit 0; fi
            if [ -n \"$HYPRLAND_INSTANCE_SIGNATURE\" ] || [ -d \"$rdir/hypr\" ] || pgrep -x Hyprland >/dev/null 2>&1; then echo hyprland; exit 0; fi
            if [ -n \"$NIRI_SOCKET\" ] || ls \"$rdir\"/niri*.sock >/dev/null 2>&1 || pgrep -x niri >/dev/null 2>&1; then echo niri; exit 0; fi
            if [ -n \"$SWAYSOCK\" ] || ls \"$rdir\"/sway-ipc*.sock >/dev/null 2>&1 || pgrep -x sway >/dev/null 2>&1; then echo sway; exit 0; fi
            if [ -n \"$MANGO_INSTANCE_SIGNATURE\" ] || pgrep -x mango >/dev/null 2>&1; then echo mango; exit 0; fi
            echo unknown
        "]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                let s = data.trim();
                if (s && s.length > 0 && s !== "unknown") {
                    root.detectedName = s;
                }
            }
        }
    }
}
