
    FileView {
        id: ryokuReady
        path: Quickshell.env("RYOKU_SHIMA_READY_FILE") || ""
        printErrors: false
    }
    Timer {
        interval: 100
        repeat: true
        running: Config.ready && GlobalStates.deferredPanelsReady && ryokuReady.path.length > 0
        onTriggered: {
            const family = Config.options?.panelFamily ?? "iris"
            const critical = family === "iris" ? ryokuIrisCritical : family === "ii" ? ryokuIiCritical : ryokuWaffleCritical
            const deferred = family === "iris" ? ryokuIrisDeferred : family === "ii" ? ryokuIiDeferred : ryokuWaffleDeferred
            if (critical.item && deferred.item) {
                ryokuReady.setText(String(Quickshell.processId))
                stop()
            }
        }
    }
    function ryokuSurfaceHandler(surface: string): var {
            const family = Config.options?.panelFamily ?? "iris"
            switch (surface) {
            case "launcher": case "overview": return ryokuOverview
            case "clipboard": return ryokuClipboard
            case "settings": return ryokuSettings
            case "sidebar-left": case "controls":
                return family === "waffle" ? ryokuWactionCenter : family === "iris" ? ryokuSidebarRight : ryokuControlPanel
            case "sidebar-right": case "notifications":
                return family === "waffle" ? ryokuWnotificationCenter : ryokuSidebarRight
            case "session": return ryokuSession
            case "cheatsheet": return ryokuCheatsheet
            case "tools": return ryokuDashboard
            case "ask": return ryokuSidebarLeft
            case "barToggle": return ryokuBar
            }
            return null
        }
    IpcHandler {
        target: "shell"
        function openSurface(mon: string, surface: string): void {
            const handler = root.ryokuSurfaceHandler(surface)
            if (handler) handler.toggle()
            else if (surface === "wallpaper") {
                GlobalStates.wallpaperSelectorTargetMonitor = mon
                GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
            } else if (surface === "theme") GlobalStates.openSettings()
            else if (surface === "screenshot") GlobalStates.openRegionScreenshot()
        }
        function closeSurface(mon: string, surface: string): void {
            const handler = root.ryokuSurfaceHandler(surface)
            if (handler && typeof handler.close === "function") handler.close()
        }
    }
