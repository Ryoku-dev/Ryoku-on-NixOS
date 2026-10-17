pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Native Ryoku plugin discovery for Karuma. This deliberately uses the public
// plugin ABI and the same discovery/placement helpers as QS Bar rather than
// importing QS Bar internals, so Karuma stays a first-class host of its own.
Item {
    id: root

    property var all: []
    property var barCapable: []
    property var plugins: []
    property var pluginIds: []

    readonly property string shellDir: Quickshell.env("RYOKU_SHELL_DIR")
    readonly property string discoverScript: shellDir && shellDir.length
        ? shellDir + "/quickshell/plugins/discover.sh"
        : (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
            + "/quickshell/plugins/discover.sh"
    readonly property string placeTool: shellDir && shellDir.length
        ? shellDir + "/quickshell/plugins/ryoku-plugins-place"
        : "ryoku-plugins-place"
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")

    width: 0
    height: 0

    function reload() {
        discover.running = false
        discover.running = true
    }

    function entryFor(id) {
        for (let i = 0; i < root.all.length; ++i)
            if (root.all[i] && root.all[i].id === id) return root.all[i]
        return null
    }

    function isEnabled(id) { return root.pluginIds.indexOf(String(id)) >= 0 }

    function defaultLane(id) {
        const entry = root.entryFor(String(id))
        const manifest = entry ? entry.manifest : null
        const defaults = manifest && manifest.defaults ? manifest.defaults : null
        const bar = defaults && defaults.bar ? defaults.bar : null
        const section = bar ? String(bar.section || "") : ""
        return section === "left" || section === "center" || section === "right" ? section : "right"
    }

    function setEnabled(id, on) {
        id = String(id)
        if (!id.length) return
        // The daemon performs the host + enabled mutation as one ordered action.
        // Two detached ryoku-plugins-place writes can race on plugins.json.
        Quickshell.execDetached(["ryoku-shell", "bar", on === true ? "show" : "hide", id])
    }

    function saveSetting(id, key, value) {
        const patch = ({})
        patch[String(key)] = value
        Quickshell.execDetached([root.placeTool, String(id), "settings", JSON.stringify(patch)])
    }

    function hostsBar(entry) {
        const hosts = entry && entry.manifest ? entry.manifest.hosts : null
        return Array.isArray(hosts) && hosts.indexOf("topbarGlyph") >= 0
    }

    function sync(list) {
        root.all = list
        const capable = []
        const enabled = []
        const ids = []
        for (let i = 0; i < list.length; ++i) {
            const entry = list[i]
            if (!root.hostsBar(entry)) continue
            capable.push(entry)
            if (entry.placement && entry.placement.enabled === true
                    && entry.placement.host === "topbarGlyph") {
                enabled.push(entry)
                ids.push(String(entry.id))
            }
        }
        root.barCapable = capable
        root.plugins = enabled
        root.pluginIds = ids
    }

    Process {
        id: discover
        command: ["bash", root.discoverScript, "--all"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let list = []
                try { list = JSON.parse(this.text || "[]") } catch (e) { list = [] }
                root.sync(Array.isArray(list) ? list : [])
            }
        }
    }

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
            + "/ryoku/plugins.json"
        watchChanges: true
        printErrors: false
        onFileChanged: root.reload()
    }

    FileView {
        path: root.stateHome + "/ryoku/store/revision.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: root.reload()
    }
}
