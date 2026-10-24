pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// User-owned Karuma profile library. A profile is the complete style.json
// document, including unknown future keys, so export/apply never silently drops
// settings introduced by a newer Karuma build.
Item {
    id: root

    required property var config
    property var profiles: ({})
    property string pending: ""
    property bool dirty: false

    readonly property string configRoot: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string path: configRoot + "/karuma/profiles.json"
    readonly property string dir: configRoot + "/karuma"
    readonly property var names: Object.keys(profiles).sort(function(a, b) { return a.localeCompare(b) })

    function cleanName(value) {
        return String(value || "").trim().replace(/[\\/\x00-\x1f]/g, "").slice(0, 48)
    }

    function clone(value) {
        try { return JSON.parse(JSON.stringify(value || {})) } catch (e) { return {} }
    }

    function parse(text) {
        try {
            const obj = JSON.parse(String(text || "{}"))
            return obj && typeof obj === "object" && !Array.isArray(obj) ? obj : ({})
        } catch (e) { return ({}) }
    }

    function save(name) {
        const key = cleanName(name)
        if (!key.length) return false
        const next = clone(root.profiles)
        next[key] = clone(root.config.raw)
        root.profiles = next
        root.queueWrite()
        return true
    }

    function apply(name) {
        const key = cleanName(name)
        if (!root.profiles[key]) return false
        root.config.commit(clone(root.profiles[key]))
        return true
    }

    function remove(name) {
        const key = cleanName(name)
        if (!root.profiles[key]) return false
        const next = ({})
        for (const k in root.profiles) if (k !== key) next[k] = root.profiles[k]
        root.profiles = next
        root.queueWrite()
        return true
    }

    function queueWrite() {
        root.dirty = true
        flush.restart()
    }

    function writeNow() {
        flush.stop()
        if (!root.dirty || prepare.running) return
        root.pending = JSON.stringify(root.profiles, null, 2) + "\n"
        root.dirty = false
        prepare.command = ["mkdir", "-p", root.dir]
        prepare.running = true
    }

    Timer { id: flush; interval: 180; onTriggered: root.writeNow() }

    Process {
        id: prepare
        onExited: code => {
            if (code === 0) file.setText(root.pending)
            if (root.dirty) flush.restart()
        }
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onLoaded: root.profiles = root.parse(file.text())
        onFileChanged: { if (!root.dirty && !prepare.running) reload() }
    }

    Component.onDestruction: root.writeNow()
}
