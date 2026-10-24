pragma Singleton

import QtQuick
import Quickshell
import inir.modules.common
import inir.modules.common.functions
import inir.services
import shell.services as Ryoku

// Wallpaper bridge for the vendored frame. Ryoku owns the wallpaper: the
// daemon publishes the active file (a still or a clip) and the live poster it
// extracts for the palette. The frame's glass surfaces sample that same file,
// so the bar, the island and the desktop always agree with what Ryoku paints.
// The reference kept a per-monitor wallpaper map; Ryoku's is global, so the
// multi-monitor branches fold to the single active path.
Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    // The reference modelled per-monitor wallpapers; Ryoku publishes one
    // active wallpaper for the session, so the map collapses to it.
    readonly property bool multiMonitorEnabled: false
    readonly property var wallpapersByMonitorRef: ({})
    readonly property string globalWallpaperPath: Ryoku.Session.wallpaper
    readonly property bool globalAnimationEnabled: true
    readonly property string globalFillMode: "fill"

    readonly property int screenCount: Quickshell.screens.length
    readonly property var screenNames: {
        const names = []
        for (const screen of Quickshell.screens) {
            names.push(getMonitorName(screen))
        }
        return names
    }

    // Output: effective wallpaper map per monitor, kept in the reference shape
    // ({ path, isVideo, isGif, ... }) so consumers read one structure.
    readonly property var effectivePerMonitor: {
        const map = {}
        const path = root.globalWallpaperPath
        const video = root.isVideoPath(path)
        const gif = root.isGifPath(path)
        for (const name of root.screenNames) {
            map[name] = {
                path: path,
                isVideo: video,
                isGif: gif,
                isAnimated: gif,
                hasCustomWallpaper: false,
                workspaceFirst: 1,
                workspaceLast: 1
            }
        }
        return map
    }

    function isVideoPath(path: string): bool {
        if (!path) return false
        const lower = path.toLowerCase()
        return lower.endsWith(".mp4") || lower.endsWith(".webm") || lower.endsWith(".mkv") || lower.endsWith(".avi") || lower.endsWith(".mov")
    }

    function isGifPath(path: string): bool {
        if (!path) return false
        return path.toLowerCase().endsWith(".gif")
    }

    // Monitor name for a screen: Quickshell names are the compositor names.
    function getMonitorName(screen: ShellScreen): string {
        return screen?.name ?? ""
    }

    // The monitor holding focus, through the window-manager seam.
    function getFocusedMonitor(): string {
        return String(CompositorService.currentOutput ?? "")
    }

    function refresh(): void {
        // The bridge mirrors daemon state; nothing cached to invalidate.
    }

    // The file a glass surface should sample for this screen.
    function wallpaperUrlForScreen(screen: ShellScreen): string {
        const path = root.globalWallpaperPath
        if (path.length === 0)
            return ""
        if (root.isVideoPath(path))
            return "file://" + Ryoku.Session.livePoster
        return "file://" + (path.startsWith("/") ? path : FileUtils.trimFileProtocol(path))
    }

    Component.onCompleted: {
        _log("[WallpaperListener] bridged to ryoku-shell wallpaper state")
    }
}
