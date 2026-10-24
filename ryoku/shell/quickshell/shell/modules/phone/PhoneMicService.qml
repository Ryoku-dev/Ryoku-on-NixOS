pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import shell.services

Singleton {
    id: root

    property bool available: false
    property bool running: micProcess.running
    property bool connecting: false
    property bool muted: false
    property bool monitorEnabled: Config.phone?.microphone?.monitor ?? false
    property string pulseSource: ""
    property int micGain: Math.max(0, Math.min(200, Number(Config.phone?.microphone?.micGain ?? 100)))
    property string lastError: ""
    property int elapsedMs: 0
    property string lastCommand: ""
    property string nullSinkModule: ""
    property string monitorModule: ""
    property string previousDefaultSource: ""
    property bool intentionalStop: false
    readonly property bool serviceActive: PhoneState.runtimeReady

    readonly property string sinkName: "ryoku_phone_mic"
    readonly property string sourceName: sinkName + ".monitor"

    signal stateChanged()
    signal errorOccurred(string message)

    function refresh(): void { if (root.serviceActive) dependencyProbe.running = true }

    function startMic(): void {
        if (!root.serviceActive) return
        if (root.running || root.connecting) return
        root.intentionalStop = false
        root.lastError = ""
        if (!root.available) {
            root.lastError = I18n.tr("scrcpy and pactl are required for the phone microphone")
            root.errorOccurred(root.lastError)
            return
        }
        if (!KdeConnectService.adbReachable) {
            root.lastError = I18n.tr("The phone is not reachable over ADB")
            root.errorOccurred(root.lastError)
            return
        }
        root.connecting = true
        defaultSourceProbe.running = true
    }

    function _loadSink(): void {
        loadSink.running = true
    }

    function _launch(): void {
        root.pulseSource = root.sourceName
        const args = ["env", "PULSE_SINK=" + root.sinkName, "scrcpy"]
            .concat(KdeConnectService.adbTargetArgs())
            .concat(["--no-video", "--audio-source=mic"])
        root.lastCommand = args.join(" ")
        micProcess.command = PhoneState.pdeath(args)
        micProcess.running = true
        root.setGain(root.micGain)
        if (Config.phone?.microphone?.setDefault ?? false)
            setDefaultSource.command = ["pactl", "set-default-source", root.sourceName]
        if (Config.phone?.microphone?.setDefault ?? false)
            setDefaultSource.running = true
        if (root.monitorEnabled) root._startMonitor()
    }

    function stopMic(): void {
        root.intentionalStop = true
        root.connecting = false
        if (micProcess.running) micProcess.running = false
        if (root.monitorModule) unloadMonitor.running = true
        if (root.nullSinkModule) unloadSink.running = true
        if (root.previousDefaultSource)
            restoreDefault.running = true
        root.pulseSource = ""
        root.elapsedMs = 0
        root.stateChanged()
    }

    function toggleMute(): void {
        root.muted = !root.muted
        if (root.pulseSource) {
            muteCommand.command = ["pactl", "set-source-mute", root.pulseSource, root.muted ? "1" : "0"]
            muteCommand.running = true
        }
    }

    function setGain(percent): void {
        root.micGain = Math.max(0, Math.min(200, Number(percent) || 0))
        if (root.pulseSource) {
            gainCommand.command = ["pactl", "set-source-volume", root.pulseSource, root.micGain + "%"]
            gainCommand.running = true
        }
    }

    function setMonitorEnabled(enabled): void {
        root.monitorEnabled = enabled === true
        if (!root.running) return
        if (root.monitorEnabled) root._startMonitor()
        else if (root.monitorModule) unloadMonitor.running = true
    }

    function _startMonitor(): void {
        if (!root.pulseSource || root.monitorModule || loadMonitor.running) return
        loadMonitor.running = true
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.elapsedMs += 1000
    }

    Process {
        id: dependencyProbe
        command: ["bash", "-c", "command -v scrcpy >/dev/null && command -v pactl >/dev/null"]
        running: false
        onExited: (code, status) => root.available = code === 0
    }

    Process {
        id: defaultSourceProbe
        command: ["pactl", "get-default-source"]
        running: false
        stdout: StdioCollector { id: defaultSourceOutput }
        onExited: {
            root.previousDefaultSource = defaultSourceOutput.text.trim()
            root._loadSink()
        }
    }

    Process {
        id: loadSink
        command: ["pactl", "load-module", "module-null-sink",
            "sink_name=" + root.sinkName,
            "sink_properties=device.description=Ryoku_Phone_Mic"]
        running: false
        stdout: StdioCollector { id: sinkModuleOutput }
        stderr: StdioCollector { id: sinkModuleError }
        onExited: (code, status) => {
            if (code !== 0) {
                root.connecting = false
                root.lastError = sinkModuleError.text.trim() || I18n.tr("Could not create the phone microphone source")
                root.errorOccurred(root.lastError)
                return
            }
            root.nullSinkModule = sinkModuleOutput.text.trim()
            root._launch()
        }
    }

    Process {
        id: micProcess
        running: false
        stderr: StdioCollector { id: micError }
        onStarted: {
            root.connecting = false
            root.elapsedMs = 0
            root.lastError = ""
            root.stateChanged()
        }
        onExited: (code, status) => {
            const intentional = root.intentionalStop
            root.intentionalStop = false
            root.connecting = false
            root.elapsedMs = 0
            if (code !== 0 && !intentional) {
                root.lastError = micError.text.trim() || I18n.tr("Phone microphone stopped")
                root.errorOccurred(root.lastError)
            }
            if (root.nullSinkModule) unloadSink.running = true
            root.stateChanged()
        }
    }

    Process {
        id: loadMonitor
        command: ["pactl", "load-module", "module-loopback", "source=" + root.sourceName,
            "latency_msec=40"]
        running: false
        stdout: StdioCollector { id: monitorModuleOutput }
        onExited: (code, status) => {
            if (code === 0) root.monitorModule = monitorModuleOutput.text.trim()
        }
    }

    Process {
        id: unloadMonitor
        command: ["pactl", "unload-module", root.monitorModule]
        running: false
        onExited: root.monitorModule = ""
    }

    Process {
        id: unloadSink
        command: ["pactl", "unload-module", root.nullSinkModule]
        running: false
        onExited: root.nullSinkModule = ""
    }

    Process {
        id: setDefaultSource
        running: false
    }
    Process {
        id: restoreDefault
        command: ["pactl", "set-default-source", root.previousDefaultSource]
        running: false
        onExited: root.previousDefaultSource = ""
    }
    Process { id: muteCommand; running: false }
    Process { id: gainCommand; running: false }

    Connections {
        target: KdeConnectService
        function onActiveReachableChanged() {
            if (!KdeConnectService.activeReachable) root.stopMic()
        }
    }

    onServiceActiveChanged: {
        if (root.serviceActive) root.refresh()
        else root.stopMic()
    }
    Component.onCompleted: if (root.serviceActive) refresh()
    Component.onDestruction: stopMic()
}
