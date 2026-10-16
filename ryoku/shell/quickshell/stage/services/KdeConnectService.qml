pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import shell.modules.phone as Phone

// Stage clock faces and the notification bridge run inside the shell as well
// as in the editor, so they forward to the one process-local phone singleton.
Singleton {
    id: root

    readonly property bool _enabled: Phone.KdeConnectService.serviceEnabled
    readonly property bool available: Phone.KdeConnectService.available
    readonly property bool ready: Phone.KdeConnectService.ready
    readonly property bool activeReachable: Phone.KdeConnectService.activeReachable
    readonly property bool scrcpyAvailable: Phone.KdeConnectService.scrcpyAvailable
    readonly property int notificationCount: Phone.KdeConnectService.notificationCount
    readonly property string activeDeviceId: Phone.KdeConnectService.activeDeviceId
    readonly property var activeDevice: Phone.KdeConnectService.activeDevice
    readonly property var devices: Phone.KdeConnectService.devices

    function isIgnoredNotification(notification) {
        return Phone.KdeConnectService.isIgnoredNotification(notification)
    }

    function considerTransferNotification(notification) {
        return Phone.KdeConnectService.considerTransferNotification(notification)
    }

    function dispatchActionFeedback(message, ok) {
        Phone.KdeConnectService.dispatchActionFeedback(message, ok)
    }

    function sendPing(devId, message) {
        Phone.KdeConnectService.sendPing(devId, message)
    }

    function shareUrl(url, devId) {
        Phone.KdeConnectService.shareUrl(url, devId)
    }
}
