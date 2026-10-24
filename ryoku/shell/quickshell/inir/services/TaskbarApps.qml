pragma Singleton

import inir.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland
import inir.services

Singleton {
    id: root

    readonly property bool sortingEnabled:
        (Config.options?.panelFamily ?? "ii") === "waffle"
    readonly property var apps: _apps
    property var _apps: []

    // The config mirror is a plain JSON object: it has no per-key change
    // signals, so every write lands through the singleton's configChanged.
    // Watching that is what keeps pins, ignores and identity rules live.
    Connections {
        target: Config
        function onConfigChanged() { root.scheduleAppsRebuild() }
    }

    Connections {
        target: CompositorService
        function onSortedToplevelsChanged() { root.scheduleAppsRebuild() }
        function onWindowOrderChanged() { root.scheduleAppsRebuild() }
        function onActionReadyChanged() { root.scheduleAppsRebuild() }
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.scheduleAppsRebuild() }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.scheduleAppsRebuild() }
    }

    Timer {
        id: appsRebuildTimer
        interval: 0
        repeat: false
        onTriggered: root._apps = root._buildApps()
    }

    function scheduleAppsRebuild(): void {
        appsRebuildTimer.restart()
    }

    function syncSortingDemand(): void {
        CompositorService.setSortingConsumer("waffleTaskbar",
            root.sortingEnabled)
    }

    onSortingEnabledChanged: syncSortingDemand()
    Component.onCompleted: {
        syncSortingDemand()
        scheduleAppsRebuild()
    }
    Component.onDestruction:
        CompositorService.setSortingConsumer("waffleTaskbar", false)

    // The dock keys apps by lowercase id while the pinned list keeps the desktop entry's
    // case (org.gnome.Nautilus): an exact match missed it, so Unpin pinned it a second time.
    function togglePin(appId) {
        const id = String(appId ?? "")
        if (id.length === 0)
            return
        const lower = id.toLowerCase()
        const pinned = Config.options?.dock?.pinnedApps ?? []
        const exists = pinned.some(p => String(p).toLowerCase() === lower)
        const next = exists ? pinned.filter(p => String(p).toLowerCase() !== lower)
            : pinned.concat([AppSearch.lookupDesktopEntry(id)?.id || id])
        Config.setNestedValue(["dock", "pinnedApps"], next)
    }

    function _providerToplevel(window): var {
        const handle = window?.toplevel ?? null
        const id = String(window?.nativeWindowId ?? window?.id ?? "")
        return {
            appId: handle?.appId || String(window?.app_id ?? ""),
            app_id: String(window?.app_id ?? ""),
            title: handle?.title || String(window?.title ?? ""),
            activated: window?.is_active === true || handle?.activated === true,
            minimized: window?.is_minimized === true || handle?.minimized === true,
            urgent: window?.is_urgent === true || handle?.urgent === true,
            fullscreen: window?.is_fullscreen === true || handle?.fullscreen === true,
            maximized: handle?.maximized === true,
            screens: handle?.screens ?? [],
            nativeWindowId: id,
            nativeWorkspaceId: String(window?.workspace_id ?? ""),
            _sourceKey: "wm:" + id,
            _sourceToplevel: handle,
            activate: () => CompositorService.focusWindow(id),
            close: () => CompositorService.closeWindow(id)
        }
    }

    function _buildApps(): var {
        var map = new Map();

        // Pinned apps
        const pinnedApps = Config.options?.dock?.pinnedApps ?? [];
        for (const appId of pinnedApps) {
            // Skip pinned apps with no desktop entry installed
            if (!AppSearch.lookupDesktopEntry(appId))
                continue;
            if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                pinned: true,
                toplevels: []
            }));
        }

        // Separator
        if (pinnedApps.length > 0) {
            map.set("SEPARATOR", { pinned: false, toplevels: [] });
        }

        // Ignored apps
        const ignoredRegexStrings = Config.options?.dock?.ignoredAppRegexes ?? [];
        const systemIgnored = [
            "^$", "^portal$", "^x-run-dialog$", "^kdialog$",
            "^xembedsniproxy$",
            "^org.freedesktop.impl.portal.*"
        ];
        const ignoredRegexes = ignoredRegexStrings.concat(systemIgnored)
            .map(pattern => new RegExp(pattern, "i"));

        // Provider rows are authoritative and remain actionable without a
        // foreign-toplevel handle. Protocol rows are startup fallback only.
        const providerWindows = CompositorService.windows ?? [];
        const sourceToplevels = CompositorService.actionReady
            ? providerWindows.map(window => root._providerToplevel(window))
            : (ToplevelManager.toplevels?.values ?? []);

        // Open windows
        for (const toplevel of sourceToplevels) {
            const appId = AppSearch.resolveWindowIdentity(toplevel);
            if (appId.length === 0 || ignoredRegexes.some(re => re.test(appId)))
                continue;
            const lowerAppId = appId.toLowerCase();
            if (!map.has(lowerAppId)) map.set(lowerAppId, ({
                pinned: false,
                toplevels: []
            }));
            map.get(lowerAppId).toplevels.push(toplevel);
        }

        var values = [];

        for (const [key, value] of map) {
            values.push({
                appId: key,
                toplevels: value.toplevels,
                pinned: value.pinned
            });
        }

        return values;
    }

}
