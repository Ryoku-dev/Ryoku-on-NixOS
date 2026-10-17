pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "KarumaSchema.js" as Schema

/*
 * Karuma's configuration: one object, one file.
 *
 * The file is the style file the bar style already reads
 * (~/.config/karuma/style.json); this component only extends it. The bar
 * (through KarumaPalette) and the hub both hold the same instance, so a hub edit
 * repaints the running bar at once, and the file is written a moment later.
 *
 *   raw   the object as read from disk, edited in place-by-copy, so keys this
 *         component does not know about are written back untouched
 *   conf  raw normalised by KarumaSchema: always complete, always in range
 *
 * Writes are debounced (a dragged slider is one write), atomic, and never echo
 * back over a newer in-memory edit. A file that cannot be parsed is read as
 * empty, and is copied to style.json.invalid before the first write replaces it.
 */
Item {
    id: root

    property string path: ""
    property var raw: ({})
    readonly property var conf: Schema.normalize(raw)
    property bool dirty: false
    property bool unreadable: false
    property string pending: ""

    readonly property string dir: path.length ? path.substring(0, path.lastIndexOf("/")) : ""

    function parse(text) {
        const t = String(text || "").trim();
        if (!t.length) { root.unreadable = false; return {}; }
        try {
            const v = JSON.parse(t);
            if (v && typeof v === "object" && !Array.isArray(v)) { root.unreadable = false; return v; }
        } catch (e) {
        }
        root.unreadable = true;
        return {};
    }

    // ------------------------------------------------------------ edits
    function commit(next) {
        root.raw = next;
        root.dirty = true;
        flushTimer.restart();
    }
    function set(key, value) { root.commit(Schema.withValue(root.raw, key, value)); }
    function setGap(side, value) { root.commit(Schema.withGap(root.raw, side, value)); }
    function setHidden(id, hide) { root.commit(Schema.withHidden(root.raw, id, hide)); }
    function move(id, to) { root.commit(Schema.withMoved(root.raw, id, to)); }
    function place(id, lane, to) { root.commit(Schema.withPlaced(root.raw, id, lane, to)); }
    function setModuleStyle(id, style) { root.commit(Schema.withModuleStyle(root.raw, id, style)); }
    function setModuleOption(id, key, value) { root.commit(Schema.withModuleOption(root.raw, id, key, value)); }
    function applyPreset(id) { root.commit(Schema.withPreset(root.raw, id)); }
    function setQuickHidden(id, hide) { root.commit(Schema.withQuickHidden(root.raw, id, hide)); }
    function reset(which) { root.commit(Schema.withoutKaruma(root.raw, which)); }

    // ------------------------------------------------------------ persistence
    function flushNow() {
        flushTimer.stop();
        if (!root.dirty || root.path.length === 0 || prepare.running)
            return;
        root.pending = JSON.stringify(root.raw, null, 2) + "\n";
        root.dirty = false;
        hold.restart();
        prepare.command = ["sh", "-c",
            "mkdir -p \"$1\" && { [ \"$3\" != 1 ] || cp -f \"$2\" \"$2.invalid\" 2>/dev/null || true; }",
            "sh", root.dir, root.path, root.unreadable ? "1" : "0"];
        prepare.running = true;
    }

    Timer { id: flushTimer; interval: 180; onTriggered: root.flushNow() }
    // Ignore the file-change echo of our own write.
    Timer { id: hold; interval: 700 }

    Process {
        id: prepare
        onExited: (code) => {
            file.setText(root.pending);
            root.unreadable = false;
            // an edit that arrived while the directory was being prepared
            if (root.dirty) flushTimer.restart();
        }
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: { if (!root.dirty && !hold.running && !prepare.running) reload(); }
        onLoaded: { if (!root.dirty && !hold.running && !prepare.running) root.raw = root.parse(file.text()); }
    }

    Component.onDestruction: root.flushNow()
}
