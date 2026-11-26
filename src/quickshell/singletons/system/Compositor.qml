pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property string detectedName: {
        const sessionDesktop = (Quickshell.env("XDG_SESSION_DESKTOP") || Quickshell.env("DESKTOP_SESSION") || "").toLowerCase();
        const desktop = ((typeof SystemInfo !== "undefined" && SystemInfo.desktopEnv) ? SystemInfo.desktopEnv : (Quickshell.env("XDG_CURRENT_DESKTOP") || "")).toLowerCase();
        const combined = sessionDesktop + " " + desktop;
        if (combined.indexOf("drift") !== -1) return "driftwm";
        if (combined.indexOf("umbriel") !== -1) return "umbriel";
        if (combined.indexOf("mango") !== -1) return "mango";
        if (combined.indexOf("sway") !== -1) return "sway";
        if (combined.indexOf("niri") !== -1) return "niri";
        if (combined.indexOf("hypr") !== -1) return "hyprland";
        if (Quickshell.env("DRIFTWM_SOCKET")) return "driftwm";
        if (Quickshell.env("UMBRIEL_SOCKET")) return "umbriel";
        if (Quickshell.env("MANGO_INSTANCE_SIGNATURE")) return "mango";
        if (Quickshell.env("SWAYSOCK")) return "sway";
        if (Quickshell.env("NIRI_SOCKET")) return "niri";
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) return "hyprland";
        return "unknown";
    }

    readonly property string name: detectedName

    Process {
        id: compDetector
        running: root.detectedName === "unknown"
        command: ["bash", "-c", "
            uid=$(id -u)
            rdir=\"${XDG_RUNTIME_DIR:-/run/user/$uid}\"
            if [ -n \"$DRIFTWM_SOCKET\" ] && [ -S \"$DRIFTWM_SOCKET\" ]; then echo driftwm; exit 0; fi
            if [ -n \"$HYPRLAND_INSTANCE_SIGNATURE\" ] && [ -S \"$rdir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock\" ]; then echo hyprland; exit 0; fi
            if [ -n \"$NIRI_SOCKET\" ] && [ -S \"$NIRI_SOCKET\" ]; then echo niri; exit 0; fi
            if [ -n \"$SWAYSOCK\" ] && [ -S \"$SWAYSOCK\" ]; then echo sway; exit 0; fi
            if [ -n \"$MANGO_INSTANCE_SIGNATURE\" ]; then echo mango; exit 0; fi
            if [ -n \"$UMBRIEL_SOCKET\" ] && [ -S \"$UMBRIEL_SOCKET\" ]; then echo umbriel; exit 0; fi
            if pgrep -x driftwm >/dev/null 2>&1; then echo driftwm; exit 0; fi
            if pgrep -x Hyprland >/dev/null 2>&1; then echo hyprland; exit 0; fi
            if pgrep -x niri >/dev/null 2>&1; then echo niri; exit 0; fi
            if pgrep -x sway >/dev/null 2>&1; then echo sway; exit 0; fi
            if pgrep -x mango >/dev/null 2>&1; then echo mango; exit 0; fi
            if pgrep -x umbriel >/dev/null 2>&1; then echo umbriel; exit 0; fi
            if ls \"$rdir\"/driftwm/*.sock >/dev/null 2>&1; then echo driftwm; exit 0; fi
            if ls \"$rdir\"/hypr/*/.socket.sock >/dev/null 2>&1; then echo hyprland; exit 0; fi
            if ls \"$rdir\"/niri*.sock >/dev/null 2>&1; then echo niri; exit 0; fi
            if ls \"$rdir\"/sway-ipc*.sock >/dev/null 2>&1; then echo sway; exit 0; fi
            if ls \"$rdir\"/mango*.sock >/dev/null 2>&1; then echo mango; exit 0; fi
            if ls \"$rdir\"/umbriel*.sock >/dev/null 2>&1; then echo umbriel; exit 0; fi
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
