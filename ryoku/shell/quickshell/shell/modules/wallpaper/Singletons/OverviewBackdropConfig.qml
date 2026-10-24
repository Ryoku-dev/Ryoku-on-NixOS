pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The overviewBackdrop.* keys live in ryogami.json, owned by the daemon.
Singleton {
    id: root

    readonly property string configPath: {
        const base = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return base + "/ryoku/ryogami.json";
    }

    readonly property string statePath: {
        const base = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache");
        return base + "/ryogami/overview-backdrop/state.json";
    }

    // The overviewBackdrop sub-object, refreshed on every file write below.
    property var _ob: ({})
    // The daemon's recoloured image, when auto-theme produced one.
    property string _themedPath: ""

    // On unless turned off, so an overview shows the wallpaper before anyone opens the picker.
    readonly property bool enabled: root._ob.enabled !== false
    readonly property bool blurEnabled: root._ob.blurEnabled !== false
    readonly property int blur: {
        const v = root._ob.blur;
        return Math.max(0, Math.min(200, (typeof v === "number") ? v : 20));
    }
    readonly property bool followWallpaper: root._ob.followWallpaper !== false
    readonly property bool autoTheme: root._ob.autoTheme === true
    readonly property string customPath: {
        if (root.autoTheme && root._themedPath.length > 0)
            return root._themedPath;
        return root._ob.path || "";
    }
    readonly property int dim: {
        const v = root._ob.dim;
        return Math.max(0, Math.min(100, (typeof v === "number") ? v : 0));
    }

    function _reparse() {
        let data = {};
        try {
            data = JSON.parse(file.text() || "{}");
        } catch (e) {
            data = {};
        }
        root._ob = (data && typeof data.overviewBackdrop === "object" && data.overviewBackdrop)
            ? data.overviewBackdrop : ({});
    }

    function _reparseState() {
        let data = {};
        try {
            data = JSON.parse(stateFile.text() || "{}");
        } catch (e) {
            data = {};
        }
        root._themedPath = (data && typeof data.themedPath === "string") ? data.themedPath : "";
    }

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: root._reparse()
        onFileChanged: {
            reload();
            root._reparse();
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: root._reparseState()
        onFileChanged: {
            reload();
            root._reparseState();
        }
    }
}
