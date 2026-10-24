pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import stage.modules.common

// Stage style presets capture only state Ryoku can restore through its public
// wallpaper and palette seams. This file is a user library, not a second theme
// configuration source.
Singleton {
    id: root

    readonly property string path: `${Directories.shellConfig}/style-presets.json`
    property var presets: []
    property bool ready: false
    property string lastError: ""
    property bool directoryReady: false

    function cleanName(value) {
        return String(value ?? "").replace(/[\/\\"]/g, "").trim();
    }

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function normalise(entries) {
        if (!Array.isArray(entries))
            return [];
        const result = [];
        const names = [];
        for (const candidate of entries) {
            if (!candidate || typeof candidate !== "object")
                continue;
            const name = root.cleanName(candidate.name);
            if (name === "" || names.includes(name))
                continue;
            names.push(name);

            const rawMode = candidate.mode !== undefined
                ? String(candidate.mode)
                : typeof candidate.darkMode === "boolean"
                    ? (candidate.darkMode ? "dark" : "light") : "smart";
            const mode = ["dark", "light", "smart", "sun"].includes(rawMode)
                ? rawMode : "smart";
            const rawScheme = String(candidate.schemeType ?? "scheme-tonal-spot");
            const scheme = rawScheme === "scheme-auto"
                ? "scheme-tonal-spot" : rawScheme;
            const rawIndex = Number(candidate.sourceColorIndex ?? 0);
            const sourceIndex = Number.isFinite(rawIndex)
                ? Math.max(0, Math.min(4, Math.round(rawIndex))) : 0;

            result.push({
                name: name,
                wallpaper: String(candidate.wallpaper ?? ""),
                theme: String(candidate.theme ?? "Wallpaper"),
                mode: mode,
                schemeType: scheme,
                sourceColorIndex: sourceIndex,
                updatedAt: Number(candidate.updatedAt ?? 0)
            });
        }
        return result;
    }

    function replace(entries) {
        const next = root.normalise(entries);
        root.presets = next;
        root.lastError = "";
        presetFile.setText(JSON.stringify({
            version: 2,
            presets: next
        }, null, 2) + "\n");
    }

    function upsert(name, state) {
        const clean = root.cleanName(name);
        if (clean === "")
            return false;
        const next = root.clone(root.presets);
        const entry = Object.assign({}, state, {
            name: clean,
            updatedAt: Date.now()
        });
        const index = next.findIndex(candidate => candidate.name === clean);
        if (index >= 0)
            next[index] = entry;
        else
            next.push(entry);
        root.replace(next);
        return true;
    }

    function rename(oldName, newName) {
        const before = root.cleanName(oldName);
        const after = root.cleanName(newName);
        if (before === "" || after === "" || (before !== after
                && root.presets.some(candidate => candidate.name === after)))
            return false;
        const next = root.clone(root.presets);
        const index = next.findIndex(candidate => candidate.name === before);
        if (index < 0)
            return false;
        next[index].name = after;
        next[index].updatedAt = Date.now();
        root.replace(next);
        return true;
    }

    function remove(name) {
        const clean = root.cleanName(name);
        const next = root.presets.filter(candidate => candidate.name !== clean);
        if (next.length === root.presets.length)
            return false;
        root.replace(next);
        return true;
    }

    function ensureLoaded() {
        presetFile.reload();
    }

    Process {
        command: ["mkdir", "-p", Directories.shellConfig]
        running: true
        onExited: {
            root.directoryReady = true;
            root.ensureLoaded();
        }
    }

    FileView {
        id: presetFile
        path: root.path
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            try {
                const document = JSON.parse(text() || "{}");
                root.presets = root.normalise(Array.isArray(document)
                    ? document : document.presets);
                root.lastError = "";
            } catch (error) {
                root.presets = [];
                root.lastError = qsTr("Saved presets could not be read.");
            }
            root.ready = true;
        }
        onLoadFailed: error => {
            if (!root.directoryReady)
                return;
            if (error === FileViewError.FileNotFound) {
                root.presets = [];
                root.lastError = "";
                root.ready = true;
            } else {
                root.lastError = qsTr("Saved presets could not be read.");
            }
        }
    }

}
