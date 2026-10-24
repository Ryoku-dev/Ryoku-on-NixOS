import QtQuick
import "../ryoku/shell/quickshell/shell/modules/desktop" as Desktop
import "../ryoku/shell/quickshell/shell/modules/wallpaper" as Wallpaper

Item {
    id: root

    Desktop.ReloadReadiness {
        id: gate
        width: 0
        height: 0
        configReady: false
    }
    Wallpaper.WallpaperFrame {
        id: frame
        screenName: "DP-1"
    }

    Component.onCompleted: {
        if (gate.ready)
            throw new Error("zero-geometry desktop became ready")
        gate.width = 2560
        gate.height = 1600
        if (gate.ready)
            throw new Error("desktop became ready before config")
        // No plugin registry is started in this test. Built-in widgets
        // must still load when their config and geometry are ready.
        gate.configReady = true
        if (!gate.ready)
            throw new Error("desktop remained blocked on plugin discovery")
        gate.width = 0
        if (gate.ready)
            throw new Error("zero-sized output kept widgets active")
        gate.width = 2560
        if (!gate.ready)
            throw new Error("widgets did not recover after output geometry returned")
        if (frame.ready)
            throw new Error("wallpaper frame was ready before data")
        if (!frame.apply(JSON.stringify({ default: { path: "/tmp/default.png", revision: 1, fit: "Cover", live: false, transition: null }, outputs: { "DP-1": { path: "/tmp/override.png", revision: 2, fit: "Contain", live: true, transition: null } } })))
            throw new Error("valid wallpaper frame was rejected")
        if (!frame.ready || frame.path !== "/tmp/override.png" || !frame.live)
            throw new Error("wallpaper output override was not applied")
        const oldPath = frame.path
        if (frame.apply("{"))
            throw new Error("malformed wallpaper frame was accepted")
        if (frame.path !== oldPath)
            throw new Error("malformed wallpaper frame blanked state")
        Qt.quit()
    }
}
