pragma ComponentBehavior: Bound

import QtQuick
import "."
import Ryoku.Ui.Singletons

Item {
    id: root

    property var kit: null
    property string query: ""
    property bool current: false
    readonly property int matches: {
        const catalogRevision = commandCatalog.revision;
        const storeRevision = commandStore.revision;
        return root.matching(root.allEntries(), root.query).length;
    }
    readonly property var rail: {
        const catalogRevision = commandCatalog.revision;
        const storeRevision = commandStore.revision;
        return root.makeRail();
    }
    property string railCurrent: "group:ryoku:start"
    readonly property bool ready: commandCatalog.ready && commandStore.ready
    readonly property bool railReady: commandCatalog.ready && commandStore.ready
    readonly property int catalogRevision: commandCatalog.revision
    readonly property var entries: {
        const catalogRevision = commandCatalog.revision;
        const storeRevision = commandStore.revision;
        const result = [];
        for (const original of commandCatalog.entries) {
            const entry = Object.assign({}, original);
            entry.favourite = commandStore.isFavourite(entry.id);
            result.push(entry);
        }
        for (const original of commandStore.commands) {
            const entry = Object.assign({}, original);
            entry.favourite = commandStore.isFavourite(entry.id);
            result.push(entry);
        }
        return result;
    }

    signal requestClose

    property bool _everLoaded: false
    property bool _restoringRail: false
    property bool _railRestored: false
    property bool _railEnsureQueued: false
    readonly property CommandsView view: viewLoader.item as CommandsView

    function libraryMeta(id) {
        for (const library of commandCatalog.libraries) {
            if (library.id === id)
                return library;
        }
        return { id: id, label: id.charAt(0).toUpperCase() + id.slice(1), groups: [] };
    }

    function libraryLabel(id) {
        if (id === "saved")
            return I18n.tr("Saved");
        return I18n.tr(root.libraryMeta(id).label);
    }

    function groupLabel(libraryId, groupId) {
        if (groupId === "start")
            return I18n.tr("Start here");
        if (groupId === "favourites")
            return I18n.tr("Favourites");
        if (groupId === "my-commands")
            return I18n.tr("My commands");
        const groups = root.libraryMeta(libraryId).groups;
        for (const group of groups) {
            if (group.id === groupId)
                return I18n.tr(group.label);
        }
        return groupId;
    }

    function allEntries() {
        return root.entries;
    }

    function searchMatch(entry, text) {
        const needle = String(text || "").trim().toLowerCase();
        if (needle.length === 0)
            return true;
        const haystack = [
            entry.title || entry.name || "",
            entry.command || "",
            entry.description || "",
            entry.tool || ""
        ].concat(entry.tags || []).join("\n").toLowerCase();
        return haystack.indexOf(needle) >= 0;
    }

    function matching(entries, text) {
        return entries.filter(entry => root.searchMatch(entry, text));
    }

    function railLibrary(railId) {
        const value = String(railId || "");
        if (value.startsWith("library:"))
            return value.slice(8);
        if (value.startsWith("group:")) {
            const parts = value.split(":");
            return parts.length > 1 ? parts[1] : "ryoku";
        }
        return "ryoku";
    }

    function railGroup(railId) {
        const value = String(railId || "");
        if (!value.startsWith("group:"))
            return root.railLibrary(value) === "saved" ? "favourites" : "start";
        const parts = value.split(":");
        return parts.length > 2 ? parts.slice(2).join(":") : "start";
    }

    function defaultRail(libraryId) {
        return libraryId === "saved" ? "group:saved:favourites" : "group:" + libraryId + ":start";
    }

    function entriesFor(libraryId, groupId, text) {
        const all = root.allEntries();
        let result = [];
        if (libraryId === "saved") {
            if (groupId === "favourites")
                result = all.filter(entry => entry.favourite);
            else
                result = all.filter(entry => entry.source === "user");
        } else if (groupId === "start") {
            result = all.filter(entry => entry.library === libraryId && entry.featured === true);
        } else {
            result = all.filter(entry => entry.library === libraryId && entry.group === groupId);
        }
        return root.matching(result, text);
    }

    function libraryEntries(libraryId) {
        const all = root.allEntries();
        if (libraryId !== "saved")
            return all.filter(entry => entry.library === libraryId);
        const seen = {};
        return all.filter(entry => {
            if (entry.source !== "user" && !entry.favourite)
                return false;
            if (seen[entry.id])
                return false;
            seen[entry.id] = true;
            return true;
        });
    }

    function makeRail() {
        const selectedLibrary = root.railLibrary(root.railCurrent);
        const searching = root.query.length > 0;
        const result = [];
        for (const libraryId of ["ryoku", "linux", "saved"]) {
            const libraryCount = root.matching(root.libraryEntries(libraryId), searching ? root.query : "").length;
            result.push({
                id: "library:" + libraryId,
                label: root.libraryLabel(libraryId),
                count: libraryCount
            });
            if (libraryId !== selectedLibrary)
                continue;
            if (libraryId === "saved") {
                for (const groupId of ["favourites", "my-commands"]) {
                    result.push({
                        id: "group:saved:" + groupId,
                        label: root.groupLabel("saved", groupId),
                        count: root.entriesFor("saved", groupId, searching ? root.query : "").length,
                        indent: 1
                    });
                }
                continue;
            }
            result.push({
                id: "group:" + libraryId + ":start",
                label: root.groupLabel(libraryId, "start"),
                count: root.entriesFor(libraryId, "start", searching ? root.query : "").length,
                indent: 1
            });
            const groups = root.libraryMeta(libraryId).groups;
            for (const group of groups) {
                if (root.entriesFor(libraryId, group.id, "").length === 0)
                    continue;
                result.push({
                    id: "group:" + libraryId + ":" + group.id,
                    label: root.groupLabel(libraryId, group.id),
                    count: root.entriesFor(libraryId, group.id, searching ? root.query : "").length,
                    indent: 1
                });
            }
            const selectedId = "group:" + libraryId + ":" + root.railGroup(root.railCurrent);
            if (!commandCatalog.ready && !result.some(item => item.id === selectedId)) {
                result.push({
                    id: selectedId,
                    label: root.groupLabel(libraryId, root.railGroup(root.railCurrent)),
                    count: 0,
                    indent: 1
                });
            }
        }
        return result;
    }

    function displayRows(text, railId) {
        const rows = [];
        const searching = String(text || "").length > 0;
        if (!searching) {
            const libraryId = root.railLibrary(railId);
            const groupId = root.railGroup(railId);
            const entries = root.entriesFor(libraryId, groupId, "");
            for (let i = 0; i < entries.length; i++) {
                rows.push({
                    entry: entries[i],
                    libraryId: libraryId,
                    libraryLabel: root.libraryLabel(libraryId),
                    groupId: groupId,
                    groupLabel: root.groupLabel(libraryId, groupId),
                    firstLibrary: false,
                    firstGroup: i === 0
                });
            }
            return rows;
        }

        for (const libraryId of ["ryoku", "linux", "saved"]) {
            const groupIds = libraryId === "saved"
                ? ["favourites", "my-commands"]
                : root.libraryMeta(libraryId).groups.map(group => group.id);
            let firstLibrary = true;
            for (const groupId of groupIds) {
                const entries = root.entriesFor(libraryId, groupId, text);
                for (let i = 0; i < entries.length; i++) {
                    rows.push({
                        entry: entries[i],
                        libraryId: libraryId,
                        libraryLabel: root.libraryLabel(libraryId),
                        groupId: groupId,
                        groupLabel: root.groupLabel(libraryId, groupId),
                        firstLibrary: firstLibrary && i === 0,
                        firstGroup: i === 0
                    });
                }
                if (entries.length > 0)
                    firstLibrary = false;
            }
        }
        return rows;
    }

    function selectionLabel() {
        const libraryId = root.railLibrary(root.railCurrent);
        return root.libraryLabel(libraryId) + "  /  " + root.groupLabel(libraryId, root.railGroup(root.railCurrent));
    }

    function restoreRail() {
        if (root._railRestored || !root.kit || typeof root.kit.get !== "function")
            return;
        root._railRestored = true;
        if (root.railCurrent !== "group:ryoku:start")
            return;
        const saved = String(root.kit.get("commands.rail", "group:ryoku:start"));
        const plausible = saved.startsWith("group:ryoku:")
            || saved.startsWith("group:linux:")
            || saved === "group:saved:favourites"
            || saved === "group:saved:my-commands";
        root._restoringRail = true;
        root.railCurrent = plausible ? saved : "group:ryoku:start";
        root._restoringRail = false;
    }

    function ensureRailSelection() {
        if (!commandCatalog.ready || !commandStore.ready)
            return;
        const exists = root.rail.some(item => item.id === root.railCurrent);
        if (exists || root.railCurrent.startsWith("library:"))
            return;
        root._restoringRail = true;
        root.railCurrent = root.defaultRail(root.railLibrary(root.railCurrent));
        root._restoringRail = false;
    }

    function scheduleRailSelectionCheck() {
        if (root._railEnsureQueued)
            return;
        root._railEnsureQueued = true;
        Qt.callLater(() => {
            root._railEnsureQueued = false;
            root.ensureRailSelection();
        });
    }

    function railSelectionChanged() {
        const selected = root.railCurrent;
        if (selected.startsWith("library:")) {
            Qt.callLater(() => {
                if (root.railCurrent === selected)
                    root.railCurrent = root.defaultRail(root.railLibrary(selected));
            });
            return;
        }
        if (root._restoringRail || !root.kit || typeof root.kit.set !== "function")
            return;
        Qt.callLater(() => {
            if (root.railCurrent === selected)
                root.kit.set("commands.rail", selected);
        });
    }

    function activate() {
        commandCatalog.start();
        root._everLoaded = true;
        if (root.view)
            Qt.callLater(root.view.activate);
    }

    function handleEscape() {
        return root.view ? root.view.handleEscape() : false;
    }

    onCurrentChanged: {
        if (root.current) {
            commandCatalog.start();
            root._everLoaded = true;
            Qt.callLater(root.activate);
        }
    }

    onKitChanged: root.restoreRail()

    onRailChanged: root.scheduleRailSelectionCheck()

    onRailCurrentChanged: root.railSelectionChanged()

    CommandCatalog {
        id: commandCatalog
        onReadyChanged: root.scheduleRailSelectionCheck()
    }
    CommandStore {
        id: commandStore
        catalogue: commandCatalog
        onReadyChanged: root.scheduleRailSelectionCheck()
    }

    Loader {
        id: viewLoader
        anchors.fill: parent
        active: root._everLoaded || root.current

        sourceComponent: CommandsView {
            controller: root
            store: commandStore
            query: root.query
            railCurrent: root.railCurrent
            active: root.current
            onRequestClose: root.requestClose()
        }
    }
}
