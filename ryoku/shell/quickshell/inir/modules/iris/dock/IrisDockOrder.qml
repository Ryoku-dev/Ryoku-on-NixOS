pragma Singleton

import QtQuick
import Quickshell
import inir.services
import inir.modules.common
import shell.services as Ryoku

// The Dock order is shared by every output. Pinned apps keep their saved order;
// open apps keep the order in which their first window appeared.
Singleton {
    id: root

    readonly property string arrange: String(Config.options?.iris?.dock?.arrange ?? "pinned")
    readonly property bool groupOpen: root.arrange === "opened"
    property var openOrder: []

    function windowIdentity(toplevel): var {
        return toplevel?.nativeWindowId ?? toplevel?._sourceKey ?? ""
    }
    function compareIdentity(left, right): real {
        const leftNumber = Number(left)
        const rightNumber = Number(right)
        if (String(left).length > 0 && String(right).length > 0
                && Number.isFinite(leftNumber) && Number.isFinite(rightNumber))
            return leftNumber - rightNumber
        return String(left).localeCompare(String(right))
    }
    function firstWindow(app): var {
        let first = null
        for (const toplevel of app?.toplevels ?? []) {
            const identity = root.windowIdentity(toplevel)
            if (first === null || root.compareIdentity(identity, first) < 0) first = identity
        }
        return first ?? ""
    }
    function compareFirstWindow(left, right): real {
        return root.compareIdentity(root.firstWindow(left), root.firstWindow(right))
    }

    readonly property var apps: {
        const source = Array.from(TaskbarApps.apps ?? []).filter(app =>
            app && app.appId !== "SEPARATOR" && (app.toplevels?.length ?? 0) > 0)
        const pins = Ryoku.Dock.pinnedOrStarter()
        const pinned = []
        for (const pin of pins) {
            const running = source.find(app => Ryoku.Dock.sameApp(app.appId, pin))
            pinned.push(Object.assign({}, running ?? {}, {
                appId: pin,
                pinned: true,
                toplevels: running?.toplevels ?? []
            }))
        }
        const unpinned = source.filter(app => !pins.some(pin => Ryoku.Dock.sameApp(pin, app.appId)))
            .map(app => Object.assign({}, app, {
                appId: Ryoku.Dock.canonicalId(app.appId),
                pinned: false
            }))
        return pinned.concat(unpinned)
    }
    readonly property var running: root.apps.filter(app => (app.toplevels?.length ?? 0) > 0)
    readonly property var liveOrder: {
        const known = root.openOrder.filter(id => root.running.some(app => app.appId === id))
        const fresh = root.running.filter(app => !known.includes(app.appId))
            .sort((left, right) => root.compareFirstWindow(left, right))
            .map(app => app.appId)
        return known.concat(fresh)
    }
    onLiveOrderChanged: if (JSON.stringify(root.liveOrder) !== JSON.stringify(root.openOrder)) orderSync.restart()
    Timer { id: orderSync; interval: 0; onTriggered: root.openOrder = root.liveOrder }

    readonly property var entries: {
        const order = root.liveOrder
        const pinned = root.apps.filter(app => app.pinned && (!root.groupOpen || (app.toplevels?.length ?? 0) === 0))
        const open = root.running.filter(app => root.groupOpen || !app.pinned)
            .sort((a, b) => order.indexOf(a.appId) - order.indexOf(b.appId))
        return pinned.length > 0 && open.length > 0
            ? pinned.concat([{ appId: "SEPARATOR" }], open)
            : pinned.concat(open)
    }

    function key(appId): string {
        return Ryoku.Dock.canonicalId(String(appId ?? ""))
    }

    function isPinned(appId: string): bool {
        return Ryoku.Dock.pinnedOrStarter().some(pin => Ryoku.Dock.sameApp(pin, appId))
    }

    function drop(appId: string, ids: var): bool {
        const at = ids.indexOf(appId)
        if (at < 0) return false
        const split = ids.indexOf("SEPARATOR")
        const app = root.entries.find(entry => entry.appId === appId)
        const running = (app?.toplevels?.length ?? 0) > 0
        const wasPinned = root.isPinned(appId)
        const toPinned = split >= 0 ? at < split : (wasPinned && (!root.groupOpen || !running))

        if (toPinned) {
            const pinned = Ryoku.Dock.pinnedOrStarter()
            const own = pinned.find(pin => Ryoku.Dock.sameApp(pin, appId)) ?? root.key(appId)
            const rest = pinned.filter(pin => !Ryoku.Dock.sameApp(pin, appId))
            const before = ids.slice(0, split >= 0 ? split : ids.length).map(id => root.key(id))
            rest.splice(root.insertAt(rest.map(id => root.key(id)), before, at), 0, own)
            if (JSON.stringify(rest) !== JSON.stringify(pinned)) Ryoku.Dock.setPinned(rest)
            return true
        }
        if (!running) return false
        if (wasPinned && !root.groupOpen) Ryoku.Dock.togglePin(appId)
        const rest = root.openOrder.filter(id => id !== appId)
        const side = split >= 0 ? split + 1 : 0
        rest.splice(root.insertAt(rest, ids.slice(side), at - side), 0, appId)
        root.openOrder = rest
        return true
    }

    function insertAt(list: var, ids: var, at: int): int {
        for (let i = at - 1; i >= 0; i--) {
            const index = list.indexOf(ids[i])
            if (index >= 0) return index + 1
        }
        for (let i = at + 1; i < ids.length; i++) {
            const index = list.indexOf(ids[i])
            if (index >= 0) return index
        }
        return list.length
    }
}
