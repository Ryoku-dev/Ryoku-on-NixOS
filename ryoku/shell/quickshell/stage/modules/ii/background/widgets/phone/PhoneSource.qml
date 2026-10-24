import QtQuick
import Quickshell
import Quickshell.Io
import stage
import stage.services
import stage.modules.common
/*
 * The Phone widgets' view of the active KDE Connect phone and of its scrcpy
 * mirror, with the same actions as the dock's phone button: mirror (or focus
 * the running one), stop, send files, send the clipboard. A send answers with
 * a short "sent" beat the widgets show on the key.
 */
QtObject {
    id: root

    property bool enabled: true

    readonly property string deviceId: KdeConnectService.activeDeviceId
    readonly property var device: KdeConnectService.activeDevice
    readonly property bool hasDevice: root.deviceId !== "" && KdeConnectService.activeReachable
    readonly property string name: KdeConnectService.activeDeviceDisplayName || Translation.tr("No phone")
    readonly property int charge: root.device?.charge ?? -1
    readonly property bool charging: root.device?.isCharging === true
    readonly property string imageSource: BluetoothDeviceImages.phoneImageFor(
        KdeConnectService.activeDeviceDisplayName, root.device?.name ?? "")

    readonly property bool mirrorAvailable: KdeConnectService.mirrorAvailable
    readonly property bool mirrorRunning: KdeConnectService.mirrorRunning
    readonly property bool mirrorLaunching: KdeConnectService.mirrorLaunching
    readonly property bool canMirror: root.enabled && root.hasDevice && root.mirrorAvailable

    readonly property string status: {
        if (!KdeConnectService.available)
            return Translation.tr("KDE Connect is off");
        if (!root.hasDevice)
            return Translation.tr("Not connected");
        if (!root.mirrorAvailable)
            return Translation.tr("scrcpy unavailable");
        if (root.mirrorRunning)
            return Translation.tr("Mirroring");
        if (root.mirrorLaunching)
            return Translation.tr("Starting mirror…");
        if (!KdeConnectService.adbReachable)
            return Translation.tr("Connected · no ADB");
        return Translation.tr("Connected");
    }

    // The last send, for a beat ("clipboard").
    property string sent: ""
    property Timer sentTimer: Timer {
        interval: 1800
        onTriggered: root.sent = ""
    }

    function mirror() {
        if (!root.canMirror)
            return;
        if (root.mirrorRunning) {
            KdeConnectService.focusMirror();
            return;
        }
        if (!root.mirrorLaunching)
            KdeConnectService.openMirrorWindow();
    }

    function stopMirror() {
        if (root.enabled)
            KdeConnectService.stopMirroring();
    }

    function sendFile() {
        if (!root.enabled || !root.hasDevice || filePicker.running)
            return;
        filePicker.running = true;
    }

    function sendClipboard() {
        if (!root.enabled || !root.hasDevice)
            return;
        KdeConnectService.sendClipboard(Quickshell.clipboardText, root.deviceId);
        root.sent = "clipboard";
        root.sentTimer.restart();
    }

    function ring() {
        if (root.enabled && root.hasDevice)
            KdeConnectService.findMyPhone(root.deviceId);
    }

    property Process filePicker: Process {
        command: ["bash", "-c",
            "if command -v kdialog >/dev/null 2>&1; then kdialog --getopenfilename \"$HOME\" --multiple 2>/dev/null | tr '\\n' '|'; "
            + "elif command -v zenity >/dev/null 2>&1; then zenity --file-selection --multiple --separator '|' 2>/dev/null; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = this.text.trim().split("|").map(path => path.trim()).filter(path => path.length > 0);
                if (paths.length > 0)
                    KdeConnectService.sendFile(paths, root.deviceId);
            }
        }
    }
}
