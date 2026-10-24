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
    property bool running: cameraProcess.running
    property bool connecting: false
    property string videoDevice: ""
    property string lastError: ""
    property int elapsedMs: 0
    property string lastCommand: ""
    property string facingOverride: ""
    property int widthOverride: 0
    property int heightOverride: 0
    property int fpsOverride: 0
    property bool intentionalStop: false
    readonly property bool serviceActive: PhoneState.runtimeReady

    readonly property var options: Config.phone?.webcam ?? ({})
    readonly property string facing: facingOverride || String(options.cameraFacing || "back")
    readonly property int width: widthOverride || Math.max(320, Number(options.width || 1280))
    readonly property int height: heightOverride || Math.max(240, Number(options.height || 720))
    readonly property int fps: fpsOverride || Math.max(1, Number(options.fps || 30))

    signal stateChanged()
    signal errorOccurred(string message)

    function refresh(): void {
        if (!root.serviceActive) return
        availabilityProbe.running = true
        loopbackProbe.running = true
    }

    function setFacing(value): void {
        const clean = String(value) === "front" ? "front" : "back"
        root.facingOverride = clean
        if (root.running) root._restart()
    }

    function setResolution(newWidth, newHeight): void {
        root.widthOverride = Math.max(320, Number(newWidth) || 1280)
        root.heightOverride = Math.max(240, Number(newHeight) || 720)
        if (root.running) root._restart()
    }

    function setFps(value): void {
        root.fpsOverride = Math.max(1, Number(value) || 30)
        if (root.running) root._restart()
    }

    function _restart(): void {
        root.stopCamera()
        restartTimer.restart()
    }

    function startCamera(): void {
        if (!root.serviceActive) return
        if (root.running || root.connecting) return
        root.intentionalStop = false
        root.lastError = ""
        if (!root.available) {
            root.lastError = I18n.tr("scrcpy is not installed")
            root.errorOccurred(root.lastError)
            return
        }
        if (!KdeConnectService.adbReachable) {
            root.lastError = I18n.tr("The phone is not reachable over ADB")
            root.errorOccurred(root.lastError)
            return
        }
        if (!root.videoDevice) {
            root.lastError = I18n.tr("No Ryoku Phone camera device is available. Enable Phone in Ryoku Settings, then reload the v4l2loopback module.")
            root.errorOccurred(root.lastError)
            return
        }
        const args = ["scrcpy"].concat(KdeConnectService.adbTargetArgs()).concat([
            "--video-source=camera",
            "--camera-facing=" + root.facing,
            "--camera-size=" + root.width + "x" + root.height,
            "--camera-fps=" + root.fps,
            "--no-audio",
            "--no-playback",
            "--v4l2-sink=" + root.videoDevice
        ])
        root.lastCommand = args.join(" ")
        root.connecting = true
        root.elapsedMs = 0
        cameraProcess.command = PhoneState.pdeath(args)
        cameraProcess.running = true
        root.stateChanged()
    }

    function stopCamera(): void {
        root.intentionalStop = true
        restartTimer.stop()
        root.connecting = false
        if (cameraProcess.running) cameraProcess.running = false
        root.elapsedMs = 0
        root.stateChanged()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.elapsedMs += 1000
    }

    Timer {
        id: restartTimer
        interval: 350
        repeat: false
        onTriggered: root.startCamera()
    }

    Process {
        id: availabilityProbe
        command: ["bash", "-c", "command -v scrcpy >/dev/null 2>&1"]
        running: false
        onExited: (code, status) => root.available = code === 0
    }

    Process {
        id: loopbackProbe
        command: ["bash", "-c",
            "preferred='" + String(root.options.videoDevice || "").replace(/'/g, "") + "'; "
            + "if [ -n \"$preferred\" ] && [ -c \"$preferred\" ]; then printf '%s\\n' \"$preferred\"; exit; fi; "
            + "for name in /sys/class/video4linux/video*/name; do [ -r \"$name\" ] || continue; "
            + "case \"$(cat \"$name\")\" in *'Ryoku Phone'*|*v4l2loopback*) printf '/dev/%s\\n' \"$(basename \"$(dirname \"$name\")\")\"; exit;; esac; done; "
            + "[ -c /dev/video10 ] && printf '/dev/video10\\n'"]
        running: false
        stdout: StdioCollector { id: loopbackOutput }
        onExited: root.videoDevice = loopbackOutput.text.trim()
    }

    Process {
        id: cameraProcess
        running: false
        stdout: StdioCollector { }
        stderr: StdioCollector { id: cameraError }
        onStarted: {
            root.connecting = false
            root.lastError = ""
            root.stateChanged()
        }
        onExited: (code, status) => {
            const intentional = root.intentionalStop
            root.intentionalStop = false
            root.connecting = false
            root.elapsedMs = 0
            if (code !== 0 && !intentional) {
                const detail = cameraError.text.trim()
                root.lastError = detail || I18n.tr("Phone camera stopped")
                root.errorOccurred(root.lastError)
            }
            root.stateChanged()
        }
    }

    Connections {
        target: KdeConnectService
        function onActiveReachableChanged() {
            if (!KdeConnectService.activeReachable) root.stopCamera()
        }
    }

    onServiceActiveChanged: {
        if (root.serviceActive) root.refresh()
        else root.stopCamera()
    }
    Component.onCompleted: if (root.serviceActive) refresh()
}
