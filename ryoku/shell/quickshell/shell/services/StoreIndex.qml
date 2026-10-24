import QtQuick
import Quickshell
import Quickshell.Io

// One RyoStore index of products the shell runs in place (<category>.json of
// receipt-owned views). The Store rewrites the index atomically and bumps its
// revision after every transaction, so a product installed, updated or removed
// while the shell runs joins or leaves without a restart. Each consumer
// validates the rows it loads.
Scope {
    id: root

    required property string category
    readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku/store"
    property var rows: []
    // true once the index has been read (or found absent), so a host does not
    // run its default first and then switch to a Store pick
    property bool ready: false
    property string revisionKey: ""

    function parse(raw) {
        try {
            const value = JSON.parse(raw || "[]");
            return Array.isArray(value) ? value : [];
        } catch (e) {
            return [];
        }
    }

    function loadRevision(raw) {
        try {
            const revision = JSON.parse(raw || "{}");
            if (revision.category !== root.category)
                return;
            const key = String(revision.revision || "") + ":" + String(revision.id || "");
            if (key === root.revisionKey)
                return;
            root.revisionKey = key;
            indexFile.reload();
        } catch (e) {
        }
    }

    FileView {
        id: indexFile
        path: root.stateRoot + "/" + root.category + ".json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.rows = root.parse(text());
            root.ready = true;
        }
        onLoadFailed: {
            root.rows = [];
            root.ready = true;
        }
    }

    FileView {
        path: root.stateRoot + "/revision.json"
        blockLoading: false
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.loadRevision(text())
    }
}
