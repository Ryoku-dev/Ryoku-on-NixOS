import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: controller

    property bool active: false
    readonly property bool hubAvailable: Settings.available("lighting")
    property var snapshot: ({ hub: hubAvailable, busy: false, op: "", report: null, error: "", seq: -1 })
    readonly property var report: snapshot && snapshot.report ? snapshot.report : null
    readonly property bool busy: snapshot && snapshot.busy === true
    readonly property string operation: snapshot && snapshot.op ? String(snapshot.op) : ""
    readonly property string error: snapshot && snapshot.error ? String(snapshot.error) : ""
    property var devicesByKey: ({})
    property var deviceKeys: []
    property bool hasScanned: false

    property string pendingKey: ""
    property var pendingPatch: ({})
    property var optimisticReport: ({})
    property var optimisticDevices: ({})

    visible: false

    onActiveChanged: {
        if (controller.active)
            controller.ensureSnapshot()
        else
            controller.flushPending()
    }

    onHubAvailableChanged: controller.ensureSnapshot()

    Connections {
        target: Daemon
        function onEvent(name, data) {
            if (name === "ryogami.lighting")
                controller.accept(data)
        }
    }

    Timer {
        id: settle
        interval: 260
        onTriggered: controller.flushPending()
    }

    function accept(next) {
        if (!next)
            return
        next = JSON.parse(JSON.stringify(next))
        var incoming = Number(next.seq)
        var current = controller.snapshot ? Number(controller.snapshot.seq) : -1
        if (!isNaN(incoming) && !isNaN(current) && incoming < current)
            return

        var keepOptimistic = next.busy === true || controller.pendingKey !== ""
        if (!keepOptimistic) {
            controller.optimisticReport = ({})
            controller.optimisticDevices = ({})
        } else if (next.report) {
            var reportCopy = Object.assign({}, next.report, controller.optimisticReport)
            if (Array.isArray(reportCopy.devices)) {
                var devices = reportCopy.devices.slice()
                for (var i = 0; i < devices.length; ++i) {
                    var key = String(devices[i].key || "")
                    var patch = controller.optimisticDevices[key]
                    if (patch)
                        devices[i] = Object.assign({}, devices[i], patch)
                }
                reportCopy.devices = devices
            }
            next = Object.assign({}, next, { report: reportCopy })
        }
        if (next.report && Array.isArray(next.report.devices))
            controller.syncDevices(next.report.devices)
        controller.snapshot = next
        controller.maybeAutoScan()
    }

    function ensureSnapshot() {
        if (!controller.active || !controller.hubAvailable)
            return
        if (!controller.report)
            controller.refresh()
        else
            controller.maybeAutoScan()
    }

    function maybeAutoScan() {
        if (controller.active && controller.hubAvailable && !controller.busy
                && !controller.hasScanned && controller.report && controller.report.enabled === true)
            controller.scan()
    }

    function syncDevices(devices) {
        var map = ({})
        var keys = []
        for (var i = 0; i < devices.length; ++i) {
            var key = String(devices[i].key || "")
            if (key.length === 0)
                continue
            map[key] = devices[i]
            keys.push(key)
        }
        controller.devicesByKey = map
        if (keys.join("\u0000") !== controller.deviceKeys.join("\u0000"))
            controller.deviceKeys = keys
    }

    function failed(err) {
        var message = err && err.message ? String(err.message) : I18n.tr("Lighting control did not answer.")
        controller.snapshot = Object.assign({}, controller.snapshot || ({}), { error: message })
    }

    function request(method, params) {
        if (!controller.hubAvailable)
            return
        Daemon.call("lighting." + method, params || ({}), function(result, err) {
            if (err) {
                controller.failed(err)
                return
            }
            controller.accept(result)
        })
    }

    function refresh() { controller.request("state", ({})) }
    function scan() {
        controller.hasScanned = true
        controller.request("scan", ({}))
    }

    function setEnabled(on) {
        if (on)
            controller.hasScanned = true
        controller.optimisticReport = Object.assign({}, controller.optimisticReport, { enabled: on })
        controller.mirrorReport({ enabled: on })
        controller.request("enable", { on: on })
    }

    function follow(key, on) {
        controller.mirrorDevice(key, on
            ? { managed: true, source: "accent", following: true }
            : { managed: false, following: false })
        controller.request("follow", { key: key, on: on })
    }

    function followAll(on) {
        var rep = controller.report
        if (rep && Array.isArray(rep.devices)) {
            var devices = []
            var optimistic = Object.assign({}, controller.optimisticDevices)
            for (var i = 0; i < rep.devices.length; ++i) {
                var d = Object.assign({}, rep.devices[i])
                var patch = null
                if (on && d.online === true)
                    patch = { managed: true, source: "accent", following: true }
                else if (!on && d.managed === true)
                    patch = { managed: false, following: false }
                if (patch) {
                    d = Object.assign(d, patch)
                    optimistic[String(d.key)] = Object.assign({}, optimistic[String(d.key)] || ({}), patch)
                }
                devices.push(d)
            }
            controller.optimisticDevices = optimistic
            controller.mirrorReport({ devices: devices })
        }
        controller.request("follow", { all: true, on: on })
    }

    function setDevice(key, patch) {
        controller.mirrorDevice(key, patch)
        controller.request("set", { key: key, patch: patch })
    }

    function setDeviceLater(key, patch) {
        if (controller.pendingKey !== "" && controller.pendingKey !== key)
            controller.flushPending()
        controller.pendingKey = key
        controller.pendingPatch = Object.assign({}, controller.pendingPatch, patch)
        controller.mirrorDevice(key, patch)
        settle.restart()
    }

    function flushPending() {
        if (controller.pendingKey === "")
            return
        var key = controller.pendingKey
        var patch = controller.pendingPatch
        controller.pendingKey = ""
        controller.pendingPatch = ({})
        settle.stop()
        controller.request("set", { key: key, patch: patch })
    }

    function save(key) { controller.request("save", { key: key }) }

    function release(key) {
        controller.mirrorDevice(key, { managed: false, following: false })
        controller.request("release", { key: key })
    }

    function apply() { controller.request("apply", ({})) }

    function mirrorReport(patch) {
        if (!controller.report)
            return
        var reportCopy = Object.assign({}, controller.report, patch)
        if (Array.isArray(reportCopy.devices))
            controller.syncDevices(reportCopy.devices)
        controller.snapshot = Object.assign({}, controller.snapshot, { report: reportCopy })
    }

    function mirrorDevice(key, patch) {
        var rep = controller.report
        if (!rep || !Array.isArray(rep.devices))
            return
        var change = Object.assign({}, patch)
        if (change.mode !== undefined)
            change.effect = ""
        var current = controller.devicesByKey[String(key)] || ({})
        if (change.source !== undefined)
            change.following = change.source === "accent"
                && (change.managed !== undefined ? change.managed === true : current.managed === true)
        else if (change.managed !== undefined)
            change.following = change.managed === true && current.source === "accent"
        var optimistic = Object.assign({}, controller.optimisticDevices)
        optimistic[String(key)] = Object.assign({}, optimistic[String(key)] || ({}), change)
        controller.optimisticDevices = optimistic

        var devices = rep.devices.slice()
        for (var i = 0; i < devices.length; ++i) {
            if (String(devices[i].key) !== String(key))
                continue
            devices[i] = Object.assign({}, devices[i], change)
            break
        }
        controller.mirrorReport({ devices: devices })
    }
}
