pragma Singleton
import QtQuick
import Quickshell

// Serpantinum's path contract, retargeted into Ryoku's storage: the vendored
// payload (scripts, watchers, fonts, sounds, translations) ships beside this
// module, and all per-widget state lands under the ryoku namespaces instead of
// the upstream ones.
QtObject {
    id: root

    // The vendored payload: the module root two levels above singletons/system,
    // where Frame's Loader loads this scene from. resolvedUrl hands back a URL
    // object on this Qt, so stringify before trimming.
    readonly property string payloadDir: {
        let u = Qt.resolvedUrl("../..").toString();
        if (u.indexOf("file://") === 0) u = u.substring(7);
        if (u.endsWith("/")) u = u.substring(0, u.length - 1);
        return u;
    }

    readonly property string home: Quickshell.env("HOME")
    readonly property string xdgRuntimeDir: Quickshell.env("XDG_RUNTIME_DIR")


    // Persistent data on disk
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")) + "/ryoku/python"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/ryoku/python"

    // Ephemeral data in RAM (tmpfs); ryoku's compositor name replaces the
    // upstream's, so a stray "serpantinum" run-dir never shadows this one.
    readonly property string runDir: (xdgRuntimeDir !== "" ? xdgRuntimeDir : "/tmp") + "/ryoku-python"
    readonly property string logDir: runDir + "/logs"

    readonly property string assetsPath: payloadDir + "/assets"
    readonly property string scriptsPath: payloadDir + "/scripts"
    readonly property string watchersPath: payloadDir + "/watchers"

    function getCacheDir(widgetName) {
        if (!widgetName || widgetName === "serpantinum" || cacheDir.endsWith("/" + widgetName)) {
            Quickshell.execDetached(["mkdir", "-p", cacheDir]);
            return cacheDir;
        }
        var finalPath = cacheDir + "/" + widgetName;
        Quickshell.execDetached(["mkdir", "-p", finalPath]);
        return finalPath;
    }

    function getStateDir(widgetName) {
        if (!widgetName || widgetName === "serpantinum" || stateDir.endsWith("/" + widgetName)) {
            Quickshell.execDetached(["mkdir", "-p", stateDir]);
            return stateDir;
        }
        var finalPath = stateDir + "/" + widgetName;
        Quickshell.execDetached(["mkdir", "-p", finalPath]);
        return finalPath;
    }

    function getRunDir(widgetName) {
        if (!widgetName || widgetName === "serpantinum" || runDir.endsWith("/" + widgetName)) {
            Quickshell.execDetached(["mkdir", "-p", runDir]);
            return runDir;
        }
        var finalPath = runDir + "/" + widgetName;
        Quickshell.execDetached(["mkdir", "-p", finalPath]);
        return finalPath;
    }

    function getLogDir(widgetName) {
        if (!widgetName || widgetName === "serpantinum" || logDir.endsWith("/" + widgetName)) {
            Quickshell.execDetached(["mkdir", "-p", logDir]);
            return logDir;
        }
        var finalPath = logDir + "/" + widgetName;
        Quickshell.execDetached(["mkdir", "-p", finalPath]);
        return finalPath;
    }
}
