
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
    IpcHandler {
        target: "shell"
        function openSurface(mon: string, surface: string): void {
            switch (surface) {
            case "launcher": GlobalStates.searchOpen = !GlobalStates.searchOpen; break
            case "clipboard":
                LauncherSearch.ensurePrefix(Config.options?.search?.prefix?.clipboard ?? ";")
                GlobalStates.searchOpen = true
                break
            case "overview": GlobalStates.overviewOpen = !GlobalStates.overviewOpen; break
            case "settings": GlobalStates.openSettings(); break
            case "controls": GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen; break
            case "notifications": GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen; break
            case "session": GlobalStates.sessionOpen = !GlobalStates.sessionOpen; break
            case "cheatsheet": GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen; break
            }
        }
        function closeSurface(mon: string, surface: string): void {
            GlobalStates.searchOpen = false
            GlobalStates.overviewOpen = false
            GlobalStates.sidebarRightOpen = false
            GlobalStates.sessionOpen = false
        }
    }
