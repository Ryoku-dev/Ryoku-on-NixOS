pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import stage.services
import ".."
import Ryoku.Ui.Singletons

// Runtime coordinator for the Dock Live Preview widget. Configuration keeps
// only the application identity; Toplevel objects are deliberately never
// serialized because they are compositor-owned and short-lived.
Singleton {
    id: root

    readonly property string preferredAppId: String(Config.options?.dock?.livePreviewAppId ?? "").trim()
    readonly property string normalizedPreferredAppId: TaskbarApps.normalizeAppId(root.preferredAppId)
    readonly property bool followActiveWindow: Config.options?.dock?.livePreviewFollowActiveWindow ?? true
    readonly property bool previewAvailable: Wm.caps.persistentScreenCapture === true
    onPreviewAvailableChanged: {
        if (root.previewAvailable || root.activeCaptureScreenName === "")
            return;
        root.activeCaptureScreenName = "";
        root.captureArbitrationChanged();
    }

    // A specific window selected from the picker is a runtime-only lock.
    property var lockedToplevel: null
    property int resolutionRevision: 0

    // Only the focused monitor owns a live stream. This also prevents the
    // same selected window from being captured once per visible dock.
    property string activeCaptureScreenName: ""
    signal captureArbitrationChanged()

    readonly property var resolvedApp: {
        const normalized = root.normalizedPreferredAppId;
        if (!normalized)
            return null;

        const apps = TaskbarApps.apps ?? [];
        return apps.find(app => TaskbarApps.normalizeAppId(app?.appId) === normalized) ?? null;
    }

    readonly property var candidateToplevels: {
        if (!root.previewAvailable)
            return [];
        const app = root.resolvedApp;
        if (!app)
            return [];

        const values = app.toplevels ?? [];
        return values.filter(toplevel => root.isValidCandidate(toplevel));
    }

    readonly property var desktopEntry: root.preferredAppId
        ? TaskbarApps.getCachedDesktopEntry(root.preferredAppId)
        : null

    readonly property string appName: root.desktopEntry?.name
        || root.preferredAppId
        || Translation.tr("Choose an app")

    function isToplevelPresent(toplevel) {
        if (!toplevel)
            return false;
        return (ToplevelManager.toplevels?.values ?? []).includes(toplevel);
    }

    function isValidCandidate(toplevel) {
        return root.isToplevelPresent(toplevel)
            && TaskbarApps.normalizeAppId(toplevel.appId) === root.normalizedPreferredAppId;
    }

    function windowOnScreen(toplevel, screen) {
        if (!screen || !toplevel)
            return false;
        return (toplevel.screens ?? []).some(candidate => candidate?.name === screen.name);
    }

    function selectedToplevelFor(screen) {
        if (!root.previewAvailable)
            return null;
        const candidates = root.candidateToplevels;
        if (candidates.length === 0)
            return null;

        if (!root.followActiveWindow && root.isValidCandidate(root.lockedToplevel))
            return root.lockedToplevel;

        // Prefer a window currently presented on this dock's monitor. The
        // activated window remains the fallback for windows spanning screens.
        const onScreen = candidates.find(toplevel => root.windowOnScreen(toplevel, screen));
        if (onScreen && onScreen.activated)
            return onScreen;

        const active = candidates.find(toplevel => toplevel.activated);
        if (active)
            return active;

        return onScreen ?? candidates[0] ?? null;
    }

    function setPreferredApp(appId) {
        const value = String(appId ?? "").trim();
        Config.options.dock.livePreviewAppId = value;
        root.lockedToplevel = null;
        root.resolutionRevision++;
    }

    function selectApp(appId) {
        Config.options.dock.livePreviewFollowActiveWindow = true;
        root.setPreferredApp(appId);
    }

    function selectWindow(toplevel) {
        if (!root.isToplevelPresent(toplevel) || !toplevel.appId)
            return;
        Config.options.dock.livePreviewFollowActiveWindow = false;
        Config.options.dock.livePreviewAppId = String(toplevel.appId);
        root.lockedToplevel = toplevel;
        root.resolutionRevision++;
    }

    function followActive() {
        root.lockedToplevel = null;
        Config.options.dock.livePreviewFollowActiveWindow = true;
        root.resolutionRevision++;
    }

    function clearSelection() {
        root.lockedToplevel = null;
        Config.options.dock.livePreviewAppId = "";
        root.resolutionRevision++;
    }

    function launchPreferredApp() {
        const desktopId = String(root.desktopEntry?.id ?? root.preferredAppId)
            .trim().replace(/\.desktop$/i, "");
        if (desktopId.length > 0)
            Spawn.run(["gtk-launch", desktopId]);
    }

    function activate(toplevel) {
        if (root.isValidCandidate(toplevel)) {
            toplevel.activate();
            return true;
        }
        root.launchPreferredApp();
        return false;
    }

    function canCapture(screen) {
        if (!root.previewAvailable)
            return false;
        const screenName = screen?.name ?? String(screen ?? "");
        const focusedName = Wm.focusedOutput ?? "";

        if (!screenName)
            return false;
        if (focusedName && focusedName !== screenName)
            return false;
        return root.activeCaptureScreenName === ""
            || root.activeCaptureScreenName === screenName;
    }

    function requestCapture(screen) {
        const screenName = screen?.name ?? String(screen ?? "");
        if (!root.canCapture(screenName))
            return false;

        if (root.activeCaptureScreenName !== screenName) {
            root.activeCaptureScreenName = screenName;
            root.captureArbitrationChanged();
        }
        return true;
    }

    function releaseCapture(screen) {
        const screenName = screen?.name ?? String(screen ?? "");
        if (root.activeCaptureScreenName !== screenName)
            return;
        root.activeCaptureScreenName = "";
        root.captureArbitrationChanged();
    }

    function releaseIfNotFocused() {
        const focusedName = (Wm.focusedOutput ?? "");
        if (root.activeCaptureScreenName && focusedName
                && root.activeCaptureScreenName !== focusedName) {
            root.activeCaptureScreenName = "";
            root.captureArbitrationChanged();
        }
    }

    Connections {
        target: ToplevelManager

        function onActiveToplevelChanged() {
            root.resolutionRevision++;
            root.captureArbitrationChanged();
        }
    }

    Connections {
        target: TaskbarApps

        function onAppsChanged() {
            root.resolutionRevision++;
            root.captureArbitrationChanged();
        }
    }

    Connections {
        target: Wm

        function onFocusedOutputChanged() {
            root.releaseIfNotFocused();
            root.captureArbitrationChanged();
        }
    }

    Connections {
        target: root.lockedToplevel

        function onClosed() {
            root.lockedToplevel = null;
            Config.options.dock.livePreviewFollowActiveWindow = true;
            root.resolutionRevision++;
            root.captureArbitrationChanged();
        }
    }
}
