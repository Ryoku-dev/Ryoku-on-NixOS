pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property var builtins: [
        { "id": "karuma", "name": "Karuma", "desc": "The Karuma bar shipped with Ryoku on NixOS.", "installed": true, "unavailable": false },
        { "id": "sumi", "name": "Sumi", "desc": "The framed Ryoku desktop.", "installed": true, "unavailable": false },
        { "id": "qsbar", "name": "QS Bar", "desc": "The configurable module bar.", "installed": true, "unavailable": false },
        { "id": "chroma", "name": "Chroma", "desc": "A vivid compact status bar.", "installed": true, "unavailable": false },
        { "id": "kairos", "name": "Kairos", "desc": "A centered editorial bar.", "installed": true, "unavailable": false },
        { "id": "iris", "name": "Shima", "desc": "The morphing island and frame desktop.", "installed": true, "unavailable": false },
        { "id": "python", "name": "Python", "desc": "Serpantinum's morphing stage bar.", "installed": true, "unavailable": false }
    ]
    property var items: builtins
    readonly property var chromaWidgets: [
        { "id": "identity", "label": "Launcher", "desc": "The Chroma identity button and app launcher." },
        { "id": "workspaces", "label": "Workspaces", "desc": "The workspace rail." },
        { "id": "media", "label": "Media", "desc": "Now playing, progress and playback spectrum." },
        { "id": "notifications", "label": "Notifications", "desc": "Notification state and unread count." },
        { "id": "wallpaper", "label": "Wallpaper", "desc": "Shortcut to wallpaper and theme controls." },
        { "id": "network", "label": "Network", "desc": "Current wired or wireless network state." },
        { "id": "audio", "label": "Audio", "desc": "Output volume and scroll volume control." },
        { "id": "battery", "label": "Battery", "desc": "Battery state when a battery is present." },
        { "id": "settings", "label": "Quick settings", "desc": "Shortcut to the Ryoku quick-settings surface." },
        { "id": "clock", "label": "Clock", "desc": "Time and date block." }
    ]

    function nameFor(id) {
        for (let i = 0; i < root.items.length; ++i)
            if (root.items[i].id === id)
                return root.items[i].name;
        return id;
    }

    function merge(catalog) {
        const installed = (catalog.items || []).filter(item =>
            item.category === "barstyles" && item.installed === true);
        const out = [];
        for (let i = 0; i < root.builtins.length; ++i) {
            const fallback = root.builtins[i];
            const found = installed.find(item => item.id === fallback.id);
            out.push(found ? {
                "id": found.id,
                "name": found.name || fallback.name,
                "desc": found.summary || found.description || fallback.desc,
                // OS-shipped styles cannot become uninstalled because a
                // mutable Store receipt is absent or stale.
                "installed": true,
                "active": found.active === true,
                "version": found.version || "",
                "installedVersion": found.installedVersion || "",
                "updateAvailable": false,
                "downloadPaused": false,
                "unavailable": false,
                "unavailableReason": "",
                "metadata": found.metadata || ({})
            } : fallback);
        }
        for (let i = 0; i < installed.length; ++i)
            if (!out.some(item => item.id === installed[i].id))
                out.push({
                    "id": installed[i].id,
                    "name": installed[i].name || installed[i].id,
                    "desc": installed[i].summary || installed[i].description || "",
                    "installed": true,
                    "active": installed[i].active === true,
                    "version": installed[i].version || "",
                    "installedVersion": installed[i].installedVersion || "",
                    "updateAvailable": installed[i].updateAvailable === true,
                    "downloadPaused": installed[i].downloadPaused === true,
                    "unavailable": installed[i].unavailable === true,
                    "unavailableReason": installed[i].unavailableReason || "",
                    "metadata": installed[i].metadata || ({})
                });
        root.items = out;
    }

    property Process catalogProcess: Process {
        command: ["ryostore", "catalog", "--category", "barstyles"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.merge(JSON.parse(this.text || "{}"));
                } catch (e) {
                    root.items = root.builtins;
                }
            }
        }
    }
}
