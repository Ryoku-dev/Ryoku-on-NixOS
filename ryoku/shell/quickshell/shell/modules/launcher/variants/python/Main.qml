// Python's launcher: the serpantinum app launcher, opened with Super+Space.
// The style's own surface (LauncherSurface.qml, ported 1:1 from Serpantinum by
// ilyamiro) is a bar-attached search pill: it docks under the bar edge with the
// matching corner radius, ranks apps by launch usage, and carries a Files tab
// (fzf + yazi preview) beside the app list. It rides the python style's own
// singletons (Config under the `python` namespace, ThemeBackend's palette, the
// Caching paths), so pick it together with the Python bar style for the full
// look; standalone it reads Ryoku's shell.json `python` settings too.
//
// The surface was serpantinum's private LauncherController-driven window; here
// the ryoku launcher contract drives it: this Scope is the surface's `host`
// (screen + visibility), the surface asks to close, and `shown` mirrors the
// pair so the controller settles open/close and the exit animation plays out.

//@ pragma UseQApplication

import QtQuick
import Quickshell
import "." as PythonVariant

Scope {
    id: root

    // ── launcher contract (docs/launcher.md) ─────────────────────────────────
    property bool openRequested: false
    readonly property bool shown: openRequested || closing
    property string monitor: ""
    property bool closing: false

    // The host bridge the surface binds against (the surface reads
    // host.hostScreen / host.hostVisible through these).
    property var hostScreen: null
    property alias hostVisible: root.openRequested

    function screenFor(mon) {
        if (mon && mon !== "") {
            const list = Quickshell.screens || [];
            for (let i = 0; i < list.length; i++)
                if (list[i].name === mon) return list[i];
        }
        return Quickshell.primaryScreen ?? (Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function show(mon) {
        if (mon) root.monitor = mon;
        root.hostScreen = root.screenFor(root.monitor);
        surfaceLoader.active = true;
        root.openRequested = true;
    }
    function hide() {
        if (!root.openRequested)
            return;
        root.openRequested = false;
    }
    function toggle(mon) { root.openRequested ? root.hide() : root.show(mon); }
    function stateDump() {
        const s = surfaceLoader.item;
        return {
            open: root.openRequested,
            query: s ? s.query : "",
            resultCount: s ? s.resultCount : 0,
            tab: s ? s.currentTabIndex : 0
        };
    }

    Timer {
        id: closeSettler
        interval: 700
        onTriggered: root.closing = false
    }

    Loader {
        id: surfaceLoader
        // Born closed: the surface animates its reveal on a visibility change,
        // so it must exist before the first show flips hostVisible.
        active: false
        asynchronous: false
        sourceComponent: Component {
            PythonVariant.LauncherSurface {
                host: root
                onCloseRequested: {
                    root.openRequested = false;
                    root.closing = true;
                    closeSettler.restart();
                }
            }
        }
    }
}
