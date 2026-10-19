pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Ryoku.Ui.Singletons
import "lib/screens.js" as Screens

Singleton {
    id: root

    readonly property real speedScale: root.speed === "quick" ? 0.6
        : root.speed === "calm" ? 1.5 : 1
    readonly property int enterDuration: root.motionDuration(Tokens.swap)
    readonly property int exitDuration: root.motionDuration(Tokens.move)
    readonly property var enterCurve: [0.16, 1, 0.3, 1, 1, 1]
    readonly property var exitCurve: [0, 0, 0.58, 1, 1, 1]
    readonly property string speed: preferences.speed
    readonly property var defaultSections: [
        { id: "vitals", visible: true },
        { id: "connections", visible: true },
        { id: "powerProfile", visible: true },
        { id: "media", visible: false },
        { id: "levels", visible: true },
        { id: "bottomControls", visible: true }
    ]
    readonly property var elementIds: [
        "identity", "cpu", "cpuTemperature", "liveGraph", "memory", "gpu", "network", "disk", "battery",
        "wifi", "bluetooth", "ethernet", "vpn",
        "mediaArtwork", "mediaTrack", "mediaTransport",
        "volume", "brightness",
        "lock", "sleep", "logout", "restart", "powerOff",
        "nightLight", "keepAwake", "doNotDisturb", "micMute", "gamingMode", "panelSettings", "pluginCards"
    ]
    readonly property var controls: root.normalizeControls(Config.controls)
    readonly property var visibleSections: controls.sections.filter(section => section.visible)

    function normalizeControls(value) {
        const source = value && typeof value === "object" ? value : {};
        const incoming = Array.isArray(source.sections) ? source.sections : [];
        const known = {};
        for (let i = 0; i < root.defaultSections.length; ++i)
            known[root.defaultSections[i].id] = root.defaultSections[i];
        const seen = {};
        const sections = [];
        for (let i = 0; i < incoming.length; ++i) {
            const entry = incoming[i];
            const id = typeof entry === "string" ? entry : entry && entry.id;
            if (!known[id] || seen[id])
                continue;
            seen[id] = true;
            sections.push({ id: id, visible: typeof entry === "object" && entry.visible !== undefined
                ? entry.visible === true : true });
        }
        for (let i = 0; i < root.defaultSections.length; ++i) {
            const section = root.defaultSections[i];
            if (!seen[section.id])
                sections.push({ id: section.id, visible: section.visible });
        }

        const allowed = {};
        for (let i = 0; i < root.elementIds.length; ++i)
            allowed[root.elementIds[i]] = true;
        const hidden = [];
        const hiddenSeen = {};
        const rawHidden = Array.isArray(source.hidden) ? source.hidden : [];
        for (let i = 0; i < rawHidden.length; ++i) {
            const id = String(rawHidden[i]);
            if (allowed[id] && !hiddenSeen[id]) {
                hiddenSeen[id] = true;
                hidden.push(id);
            }
        }
        return { sections: sections, hidden: hidden };
    }


    function elementVisible(id) {
        return root.controls.hidden.indexOf(id) < 0;
    }


    function screenName(screen) {
        if (typeof screen === "string")
            return screen;
        return screen && screen.name ? screen.name : "";
    }

    function sliceFor(screen) {
        const name = root.screenName(screen);
        if (name !== "")
            return Screens.sliceForName(states.instances, name);
        const focused = Screens.sliceForName(states.instances, Wm.focusedOutput);
        if (focused)
            return focused;
        return states.instances.length > 0 ? states.instances[0] : null;
    }

    function normalizedTab(tab) {
        return tab === "wifi" || tab === "bluetooth" || tab === "plugins"
            ? tab : "controls";
    }

    function isOpen(screen) {
        const slice = root.sliceFor(screen);
        return slice ? slice.open : false;
    }

    function activeTab(screen) {
        const slice = root.sliceFor(screen);
        return slice ? root.normalizedTab(slice.tab) : "controls";
    }

    function selectTab(screen, tab) {
        const slice = root.sliceFor(screen);
        if (slice)
            slice.tab = root.normalizedTab(tab);
    }

    // The trigger is taken only when the card opens, so a tab switch or the
    // close keeps the same trigger.
    function open(screen, tab, trigger) {
        const slice = root.sliceFor(screen);
        if (!slice)
            return;
        const shellSlice = ShellState.forScreen(slice.modelData);
        if (shellSlice)
            shellSlice.askOpen = false;
        if (!slice.open) {
            const local = trigger ? Screens.localRect(trigger, slice.modelData) : null;
            if (local) {
                slice.triggerX = local.x;
                slice.triggerY = local.y;
                slice.triggerWidth = local.width;
                slice.triggerHeight = local.height;
            }
            slice.anchored = local !== null;
        }
        slice.tab = root.normalizedTab(tab);
        slice.open = true;
    }

    function close(screen) {
        const slice = root.sliceFor(screen);
        if (slice)
            slice.open = false;
    }

    function closeAll() {
        const list = states.instances;
        for (let i = 0; i < list.length; ++i)
            list[i].open = false;
    }

    function toggle(screen, tab, trigger) {
        const slice = root.sliceFor(screen);
        if (!slice)
            return;
        const nextTab = root.normalizedTab(tab);
        if (slice.open && (!tab || nextTab === slice.tab))
            root.close(screen);
        else
            root.open(screen, nextTab, trigger);
    }

    function triggerFor(screen) {
        const slice = root.sliceFor(screen);
        return slice && slice.anchored
            ? { x: slice.triggerX, y: slice.triggerY, width: slice.triggerWidth, height: slice.triggerHeight }
            : null;
    }

    // A request from a widget on screen carries its global rect as ownerRect. A
    // 1x1 rect is a point rather than a widget, as it is for the frame menus.
    function triggerFrom(context) {
        const rect = context && typeof context === "object" ? context.ownerRect : null;
        if (!rect)
            return null;
        const trigger = { x: Number(rect.x), y: Number(rect.y),
            width: Number(rect.width), height: Number(rect.height) };
        const finite = isFinite(trigger.x) && isFinite(trigger.y)
            && isFinite(trigger.width) && isFinite(trigger.height);
        const widget = trigger.width > 0 && trigger.height > 0 && (trigger.width > 1 || trigger.height > 1);
        return finite && widget ? trigger : null;
    }

    function railClearances(screen) {
        const slice = root.sliceFor(screen);
        if (!slice)
            return { top: 0, left: 0, bottom: 0, right: 0 };
        return {
            top: slice.railTop,
            left: slice.railLeft,
            bottom: slice.railBottom,
            right: slice.railRight
        };
    }

    function setRailClearances(screen, clearances) {
        const slice = root.sliceFor(screen);
        if (!slice || !clearances)
            return;
        slice.railTop = Math.max(0, Number(clearances.top) || 0);
        slice.railLeft = Math.max(0, Number(clearances.left) || 0);
        slice.railBottom = Math.max(0, Number(clearances.bottom) || 0);
        slice.railRight = Math.max(0, Number(clearances.right) || 0);
    }

    // The seam of the bar style on this screen, pushed by its Frame the same way
    // as the rail clearances, so Controls welds onto that bar.
    function setSeam(screen, seam) {
        const slice = root.sliceFor(screen);
        if (!slice)
            return;
        slice.seamDepth = seam ? seam.depth : 0;
        slice.seamFillet = seam ? seam.fillet : 0;
        slice.seamRadius = seam ? seam.radius : 0;
        slice.seamMargin = seam ? seam.margin : 0;
        slice.seamFill = seam ? seam.fill : "surface";
    }

    function seamFor(screen) {
        const slice = root.sliceFor(screen);
        return slice && slice.seamDepth > 0 ? {
            edge: "top",
            depth: slice.seamDepth,
            fillet: slice.seamFillet,
            radius: slice.seamRadius,
            margin: slice.seamMargin,
            fill: slice.seamFill
        } : null;
    }

    // A welded card slides out of its bar with the bar's own panel motion, which
    // takes longer than the fade; the Controls speed setting still applies.
    function exitDurationFor(screen) {
        return root.seamFor(screen) ? root.motionDuration(Motion.morph) : root.exitDuration;
    }

    function motionDuration(base) {
        return (Motion.reduce || Tokens.reduceMotion)
            ? 0 : Math.round(base * root.speedScale);
    }

    function setSpeed(value) {
        if (value === "quick" || value === "standard" || value === "calm")
            preferences.speed = value;
    }

    function consumeRequest(requestedId, monitor, context) {
        const value = requestedId || "";
        const split = value.indexOf("#");
        const id = split >= 0 ? value.substring(0, split) : value;
        let tab = split >= 0 ? value.substring(split + 1) : "";
        if (!tab && typeof context === "string")
            tab = context.charAt(0) === "#" ? context.substring(1) : context;
        else if (!tab && context && typeof context === "object")
            tab = context.tab || context.page || "";
        if (id === "sidebar-left")
            root.toggle(monitor, tab, root.triggerFrom(context));
    }

    Connections {
        target: ShellState
        function onSurfaceRequested(id, mon, context) {
            root.consumeRequest(id, mon, context);
        }
        function onSurfaceClosed(id, mon) {
            const base = (id || "").split("#")[0];
            if (base === "sidebar-left")
                root.close(mon);
        }
    }

    PersistentProperties {
        id: preferences
        property string speed: "standard"
    }

    Variants {
        id: states
        model: ShellState.screens

        PersistentProperties {
            required property var modelData
            property bool open: false
            property string tab: "controls"
            property bool anchored: false
            property real triggerX: 0
            property real triggerY: 0
            property real triggerWidth: 0
            property real triggerHeight: 0
            property real seamDepth: 0
            property real seamFillet: 0
            property real seamRadius: 0
            property real seamMargin: 0
            property string seamFill: "surface"
            property real railTop: 0
            property real railLeft: 0
            property real railBottom: 0
            property real railRight: 0
        }
    }
}
