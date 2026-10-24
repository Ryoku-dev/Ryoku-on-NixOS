import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    property var values: ({})
    property bool ready: false
    property string pendingText: ""
    property bool directoryReady: false

    function get(key, fallback) {
        return Object.prototype.hasOwnProperty.call(root.values, key)
            ? root.values[key] : fallback;
    }

    function set(key, value) {
        const next = {};
        const names = Object.keys(root.values);
        for (let i = 0; i < names.length; i++)
            next[names[i]] = root.values[names[i]];
        next[key] = value;
        root.values = next;
        root.persist();
    }

    function load() {
        let parsed = {};
        try {
            const text = stateFile.text();
            if (text && text.trim().length > 0) {
                const candidate = JSON.parse(text);
                if (candidate && typeof candidate === "object" && !Array.isArray(candidate))
                    parsed = candidate;
            }
        } catch (e) {
            parsed = {};
        }
        root.values = parsed;
        root.ready = true;
    }

    function persist() {
        root.pendingText = JSON.stringify(root.values);
        if (root.directoryReady)
            persistDelay.restart();
    }

    function writePending() {
        if (!root.directoryReady || root.pendingText.length === 0)
            return;
        stateFile.setText(root.pendingText);
        root.pendingText = "";
    }

    Timer {
        id: persistDelay
        interval: 60
        onTriggered: root.writePending()
    }

    Process {
        id: makeStateDir
        command: ["mkdir", "-p", root.stateDir]
        running: true
        onExited: exitCode => {
            root.directoryReady = exitCode === 0;
            if (root.directoryReady && root.pendingText.length > 0)
                persistDelay.restart();
        }
    }

    FileView {
        id: stateFile
        path: root.stateDir + "/kit.json"
        blockLoading: true
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.load()
        onLoadFailed: root.load()
    }
}
