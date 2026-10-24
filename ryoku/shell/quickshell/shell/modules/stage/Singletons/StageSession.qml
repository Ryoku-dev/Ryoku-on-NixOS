pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell

// The Edit widgets session (docs/stage.md, "Session model"): one desktop, one
// monitor, never two. Selection is transient editor state; `selected` remains
// the primary member for the existing inspector and menu readers.
Singleton {
    id: root

    // "" | "widgets".
    property string mode: ""
    // The screen the session was opened on (its desktop lifts, its editor shows).
    property string monitor: ""
    // Ordered widget ids ("clock", "plugin:x"). The final member is primary.
    property var selection: []
    readonly property string selected: root.selection.length > 0
        ? root.selection[root.selection.length - 1] : ""
    // The drop-down open under a toolbar button: "" | "add".
    property string panel: ""
    // The Stage Editor catalogue the session shows ("widgets", "wallpaper",
    // "style", "visualizer", "depth"): a hand-off can open straight on the
    // editor it means, and asking again while open switches catalogue.
    property string section: "widgets"
    // The widget whose settings occupy the drawer. `inspectingBack` remembers
    // the catalogue that handed off, so the hidden page returns to its caller.
    property string inspecting: ""
    property string inspectingBack: "widgets"
    property string depthPick: ""

    readonly property bool active: root.mode !== ""
    readonly property bool widgets: root.mode === "widgets"

    signal left()

    function onMonitor(name) { return root.active && ("" + name) === root.monitor; }

    function enterWidgets(monitor, section) {
        root.selection = [];
        root.panel = "";
        root.section = section ? "" + section : "widgets";
        root.inspecting = "";
        root.inspectingBack = "widgets";
        root.monitor = "" + (monitor || "");
        root.mode = "widgets";
    }
    function openSection(section) {
        root.section = "" + section;
    }
    function leave() {
        if (!root.active)
            return;
        root.mode = "";
        root.selection = [];
        root.panel = "";
        root.inspecting = "";
        root.inspectingBack = "widgets";
        root.depthPick = "";
        root.left();
    }

    function contains(id) {
        return root.selection.indexOf("" + id) >= 0;
    }
    function select(id) {
        const value = "" + id;
        root.selection = value === "" ? [] : [value];
        if (root.inspecting !== "" && value !== "")
            root.inspecting = value;
    }
    function selectMany(ids, primary) {
        const next = [];
        for (const raw of ids || []) {
            const id = "" + raw;
            if (id !== "" && next.indexOf(id) < 0)
                next.push(id);
        }
        const main = "" + (primary || "");
        const at = next.indexOf(main);
        if (at >= 0 && at !== next.length - 1) {
            next.splice(at, 1);
            next.push(main);
        }
        root.selection = next;
        if (root.inspecting !== "" && next.length > 0)
            root.inspecting = next[next.length - 1];
    }
    function deselect() {
        root.selection = [];
    }
    function remove(id) {
        const value = "" + id;
        root.selection = root.selection.filter(member => member !== value);
        if (root.inspecting === value)
            root.inspecting = "";
    }
    function toggleSelect(id) {
        const value = "" + id;
        const next = root.selection.slice();
        const at = next.indexOf(value);
        if (at >= 0)
            next.splice(at, 1);
        else
            next.push(value);
        root.selection = next;
        if (root.inspecting !== "" && at < 0)
            root.inspecting = value;
    }

    function openPanel(kind) { root.panel = "" + kind; }
    function closePanel() { root.panel = ""; }
    function togglePanel(kind) { root.panel = root.panel === ("" + kind) ? "" : ("" + kind); }

    // Escape unwinds one level per press: an open drop-down, then the
    // selection, then the session. Returns what it did.
    function escapeStep() {
        if (root.panel !== "") {
            root.panel = "";
            return "panel";
        }
        if (root.selection.length > 0) {
            root.selection = [];
            return "selection";
        }
        root.leave();
        return "leave";
    }
}
