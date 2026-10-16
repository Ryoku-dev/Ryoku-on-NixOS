pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui as Ui
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku/phone"
    readonly property bool enabled: Config.phone?.enabled ?? false
    property bool installed: false
    property bool configured: false
    property bool networkIsolation: false
    property bool installBusy: false
    property string installAction: ""
    property string installError: ""
    property int toastSeq: 0
    property string toastText: ""
    property bool toastError: false
    property bool filesReady: false
    property bool statusForAction: false
    property bool actionSucceeded: false
    property string actionFailure: ""

    function ok(): string { return "ok" }

    function fail(reason): string {
        const text = String(reason || I18n.tr("The action failed"))
        root.showToast(text, true)
        return "err " + text
    }

    function showToast(text, error): void {
        root.toastSeq += 1
        root.toastText = String(text || "")
        root.toastError = error === true
        root.queueState()
    }

    function cleanError(raw): string {
        const lines = String(raw || "").split("\n").map(line => line.trim()).filter(line => line.length > 0)
        let text = lines.length > 0 ? lines[lines.length - 1] : I18n.tr("The action failed")
        text = text.replace(/^ryoku-hub:\s*/i, "").replace(/^error:\s*/i, "")
            .replace(/^phone (?:enable|disable|status):\s*/i, "")
        if (/dismiss|cancel|not authorized|authentication failed|authorization failed/i.test(text))
            return I18n.tr("The password prompt was dismissed")
        return text.charAt(0).toUpperCase() + text.slice(1)
    }

    function setRuntimeGate(): void {
        const ready = root.enabled && root.installed
        if (!ready && PhoneState.runtimeReady) {
            PhoneScrcpyService.stopAllSessions()
            PhoneCameraService.stopCamera()
            PhoneMicService.stopMic()
        }
        PhoneState.runtimeReady = ready
        if (ready) {
            KdeConnectService.refresh()
            KdeConnectService._probeAdb()
            PhoneScrcpyService.refresh()
            PhoneCameraService.refresh()
            PhoneMicService.refresh()
            PhoneContactsService.refresh()
        }
    }

    function refresh(): string {
        if (!statusProc.running) statusProc.running = true
        if (!networkProc.running) networkProc.running = true
        if (PhoneState.runtimeReady) KdeConnectService._probeAdb()
        root.queueState()
        return root.ok()
    }

    function setPhoneEnabled(value): void {
        settingsSocket.queued += "call settings.patch "
            + JSON.stringify({ path: "phone.enabled", value: value === true }) + "\n"
        if (settingsSocket.connected) settingsSocket.flushQueued()
        else settingsSocket.connected = true
    }

    function startInstallAction(action): string {
        if (root.installBusy) return root.fail(I18n.tr("A phone setup action is already running"))
        root.installBusy = true
        root.installAction = action
        root.installError = ""
        root.statusForAction = false
        root.actionSucceeded = false
        root.actionFailure = ""
        if (action === "remove") {
            PhoneScrcpyService.stopAllSessions()
            PhoneCameraService.stopCamera()
            PhoneMicService.stopMic()
            PhoneState.runtimeReady = false
        }
        switchProc.command = ["ryoku-hub", "phone", action === "install" ? "on" : "off"]
        switchProc.running = true
        root.queueState()
        return root.ok()
    }

    function finishInstallAction(): void {
        const action = root.installAction
        const succeeded = root.actionSucceeded
        const reason = root.actionFailure
        root.installBusy = false
        root.installAction = ""
        root.installError = succeeded ? "" : reason
        root.setRuntimeGate()
        root.queueState()
        root.showToast(succeeded
            ? (action === "install" ? I18n.tr("Phone tools are ready") : I18n.tr("Phone tools were removed"))
            : reason, !succeeded)
        if (action !== "install") return
        const title = succeeded ? I18n.tr("Phone tools are ready") : I18n.tr("Phone setup failed")
        const body = succeeded ? I18n.tr("Connect your phone in Kit to continue") : reason
        Spawn.run(["notify-send", "--app-name=Ryoku Phone", "--icon=smartphone", title, body])
        Spawn.run(["ryoku-kit", "phone"])
    }

    function queueState(): void {
        stateDebounce.restart()
    }

    function deviceRows(): var {
        return Array.from(KdeConnectService.devices || []).map(device => ({
            id: String(device.id || ""),
            name: String(device.name || ""),
            type: String(device.type || "phone") === "phone" ? "smartphone" : String(device.type || "smartphone"),
            paired: device.paired === true,
            reachable: device.reachable === true,
            charge: Number(device.charge ?? -1),
            charging: device.charging === true,
            signal: device.signalStrength === undefined ? -1 : Math.max(0, Math.min(4, Number(device.signalStrength) || 0)),
            plugins: Array.from(device.supportedPlugins || [])
        }))
    }

    function notificationRows(): var {
        return Array.from(KdeConnectService.notifications || []).map(notification => ({
            id: String(notification.publicId || ""),
            app: String(notification.appName || ""),
            title: String(notification.summary || ""),
            body: String(notification.body || ""),
            time: Number(notification.time || 0),
            icon: String(notification.iconPath || ""),
            dismissable: notification.dismissable !== false,
            canReply: String(notification.replyId || "").length > 0,
            replyHint: String(notification.replyPlaceholder || ""),
            actions: Array.from(notification.actions || []).map(action => ({
                key: String(action.key || ""), label: String(action.label || "")
            }))
        }))
    }

    function stateObject(): var {
        const nextAlarm = PhoneAlarmService.nextAt
        const callState = String(PhoneCallService.callState || "idle")
        return {
            schema: 1,
            updatedAt: Date.now(),
            enabled: root.enabled,
            installed: root.installed,
            configured: root.configured,
            install: { busy: root.installBusy, action: root.installAction, error: root.installError },
            networkIsolation: root.networkIsolation,
            kdeconnect: { running: KdeConnectService.ready, error: String(KdeConnectService.lastError || "") },
            activeDeviceId: String(KdeConnectService.activeDeviceId || ""),
            devices: root.deviceRows(),
            pairing: {
                outgoing: String(KdeConnectService.outgoingPairId || ""),
                incoming: Array.from(KdeConnectService.pairRequests || []).map(request => ({
                    id: String(request.id || ""), name: String(request.name || "")
                }))
            },
            notifications: root.notificationRows(),
            runCommands: Array.from(KdeConnectService.runCommands || []).map(command => ({
                id: String(command.id || ""), name: String(command.name || "")
            })),
            call: {
                state: callState,
                name: callState === "idle" ? "" : String(PhoneCallService.displayName || ""),
                number: callState === "idle" ? "" : String(PhoneCallService.number || "")
            },
            alarm: { nextAt: nextAlarm ? nextAlarm.getTime() : 0 },
            adb: {
                installed: root.installed || KdeConnectService.adbPresent,
                state: String(KdeConnectService.adbState || "none"),
                serial: String(KdeConnectService.resolvedAdbSerial || ""),
                wireless: KdeConnectService.adbWireless,
                model: String(KdeConnectService.adbModel || ""),
                candidates: Array.from(KdeConnectService.adbCandidates || [])
            },
            scrcpy: {
                installed: root.installed || PhoneScrcpyService.available,
                version: String(PhoneScrcpyService.version || ""),
                appMode: PhoneScrcpyService.appModeSupported
            },
            mirror: {
                running: PhoneScrcpyService.mirrorRunning,
                starting: PhoneScrcpyService.mirrorLaunching,
                recording: PhoneScrcpyService.recordingRunning,
                error: String(PhoneScrcpyService.mirrorLaunchError || PhoneScrcpyService.recordingError || "")
            },
            webcam: {
                running: PhoneCameraService.running,
                starting: PhoneCameraService.connecting,
                device: String(PhoneCameraService.videoDevice || ""),
                facing: String(PhoneCameraService.facing || "back"),
                ready: PhoneCameraService.available && String(PhoneCameraService.videoDevice || "").length > 0,
                error: String(PhoneCameraService.lastError || "")
            },
            mic: {
                running: PhoneMicService.running,
                starting: PhoneMicService.connecting,
                error: String(PhoneMicService.lastError || "")
            },
            contacts: { count: PhoneContactsService.count, ready: PhoneContactsService.ready },
            apps: {
                count: Array.from(PhoneScrcpyService.apps || []).length,
                loading: PhoneScrcpyService.appsLoading,
                error: String(PhoneScrcpyService.appsError || "")
            },
            toast: { seq: root.toastSeq, text: root.toastText, error: root.toastError }
        }
    }

    function contactRows(): var {
        return Array.from(PhoneContactsService.contacts || []).map(contact => ({
            id: String(contact.id || ""),
            name: String(contact.displayName || contact.name || ""),
            numbers: Array.from(contact.phoneNumbers || contact.phones || []).map(phone => ({
                number: String(phone.number || phone.value || ""),
                type: String(phone.type || "mobile")
            })),
            avatar: String(contact.avatarPath || contact.avatar || ""),
            favorite: PhoneContactsService.isFavorite(String(contact.id || ""))
        }))
    }

    function appRows(): var {
        return Array.from(PhoneScrcpyService.apps || []).map(app => {
            const packageName = String(app.package || "")
            return {
                package: packageName,
                label: String(app.label || app.name || packageName),
                icon: String(PhoneAppIconService.iconFor(packageName) || app.icon || ""),
                running: PhoneScrcpyService.isAppRunning(packageName),
                favorite: PhoneScrcpyService.isAppFavorite(packageName)
            }
        })
    }

    function writeState(): void {
        if (!root.filesReady) return
        stateFile.setText(JSON.stringify(root.stateObject()) + "\n")
    }

    function writeContacts(): void {
        if (!root.filesReady) return
        contactsFile.setText(JSON.stringify(root.contactRows()) + "\n")
    }

    function writeApps(): void {
        if (!root.filesReady) return
        appsFile.setText(JSON.stringify(root.appRows()) + "\n")
    }

    Timer {
        id: stateDebounce
        interval: 150
        repeat: false
        onTriggered: root.writeState()
    }

    Process {
        id: ensureDir
        command: ["mkdir", "-p", root.runtimeDir]
        environment: Spawn.env
        running: false
        onExited: {
            root.filesReady = true
            root.writeState()
            root.writeContacts()
            root.writeApps()
        }
    }

    FileView { id: stateFile; path: root.runtimeDir + "/state.json"; atomicWrites: true; printErrors: false }
    FileView { id: contactsFile; path: root.runtimeDir + "/contacts.json"; atomicWrites: true; printErrors: false }
    FileView { id: appsFile; path: root.runtimeDir + "/apps.json"; atomicWrites: true; printErrors: false }

    Process {
        id: statusProc
        command: ["ryoku-hub", "phone", "status"]
        environment: Spawn.env
        running: false
        stdout: StdioCollector { id: statusOut }
        stderr: StdioCollector { id: statusErr }
        onExited: code => {
            if (code === 0) {
                try {
                    const status = JSON.parse(statusOut.text || "{}")
                    root.installed = status.installed === true
                    root.configured = status.configured === true
                    if (root.statusForAction && root.actionSucceeded) {
                        const expectedInstalled = root.installAction === "install"
                        if (root.installed !== expectedInstalled) {
                            root.actionSucceeded = false
                            root.actionFailure = String(status.reason || I18n.tr("Phone setup did not complete"))
                        }
                    }
                } catch (error) {
                    if (root.statusForAction) {
                        root.actionSucceeded = false
                        root.actionFailure = I18n.tr("Phone status returned invalid data")
                    } else {
                        root.installError = I18n.tr("Phone status returned invalid data")
                    }
                }
            } else if (root.statusForAction) {
                root.actionSucceeded = false
                root.actionFailure = root.cleanError(statusErr.text)
            } else {
                root.installError = root.cleanError(statusErr.text)
            }
            root.setRuntimeGate()
            root.queueState()
            if (root.statusForAction) {
                root.statusForAction = false
                root.finishInstallAction()
            }
        }
    }

    Socket {
        id: settingsSocket
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-shell.sock"
        property string queued: ""
        function flushQueued(): void {
            if (!queued) return
            write(queued)
            flush()
            queued = ""
        }
        onConnectionStateChanged: if (connected) flushQueued()
    }

    Process {
        id: networkProc
        command: ["ryoku-network-kill", "status"]
        environment: Spawn.env
        running: false
        stdout: StdioCollector { id: networkOut }
        onExited: code => {
            const status = networkOut.text.trim()
            root.networkIsolation = code === 0 && status !== "off"
            root.queueState()
        }
    }

    Process {
        id: switchProc
        environment: Spawn.env
        running: false
        stderr: StdioCollector { id: switchErr }
        onExited: code => {
            root.actionSucceeded = code === 0
            root.actionFailure = code === 0 ? "" : root.cleanError(switchErr.text)
            if (code === 0)
                root.setPhoneEnabled(root.installAction === "install")
            if (statusProc.running) {
                root.statusForAction = false
                statusProc.running = false
                Qt.callLater(() => {
                    root.statusForAction = true
                    statusProc.running = true
                })
            } else {
                root.statusForAction = true
                statusProc.running = true
            }
        }
    }

    FloatingWindow {
        id: fileDialogWindow
        visible: false
        implicitWidth: 1
        implicitHeight: 1
        Ui.FileDialogHost {
            id: filePicker
            title: I18n.tr("Send a file to phone")
            currentFolder: "file://" + (Quickshell.env("HOME") || "/")
            onAccepted: {
                KdeConnectService.sendFile([String(selectedFile)], KdeConnectService.activeDeviceId)
                root.showToast(I18n.tr("File sent to the phone"), false)
            }
        }
    }

    IpcHandler {
        target: "phone"

        function refresh(): string { return root.refresh() }
        function install(): string { return root.startInstallAction("install") }
        function remove(): string { return root.startInstallAction("remove") }

        function selectDevice(id: string): string {
            if (!KdeConnectService._findDevice(id)) return root.fail(I18n.tr("That phone is no longer available"))
            KdeConnectService.selectDevice(id)
            return root.ok()
        }
        function pair(id: string): string {
            if (!id) return root.fail(I18n.tr("Choose a phone first"))
            KdeConnectService.requestPairing(id)
            return root.ok()
        }
        function unpair(id: string): string {
            if (!id) return root.fail(I18n.tr("Choose a phone first"))
            KdeConnectService.unpair(id)
            return root.ok()
        }
        function acceptPair(id: string): string {
            if (!id) return root.fail(I18n.tr("The pairing request is missing"))
            KdeConnectService.acceptPairing(id)
            return root.ok()
        }
        function rejectPair(id: string): string {
            if (!id) return root.fail(I18n.tr("The pairing request is missing"))
            KdeConnectService.rejectPairing(id)
            return root.ok()
        }
        function ring(): string {
            if (!KdeConnectService.activeReachable) return root.fail(I18n.tr("The phone is not connected"))
            KdeConnectService.findMyPhone(KdeConnectService.activeDeviceId)
            return root.ok()
        }
        function ping(): string {
            if (!KdeConnectService.activeReachable) return root.fail(I18n.tr("The phone is not connected"))
            KdeConnectService.sendPing(KdeConnectService.activeDeviceId, I18n.tr("Ping from Ryoku"))
            return root.ok()
        }
        function sendClipboard(): string {
            if (!KdeConnectService.activeReachable) return root.fail(I18n.tr("The phone is not connected"))
            KdeConnectService.sendClipboard(Quickshell.clipboardText, KdeConnectService.activeDeviceId)
            return root.ok()
        }
        function pickFiles(): string {
            if (!KdeConnectService.activeReachable) return root.fail(I18n.tr("The phone is not connected"))
            filePicker.open()
            return root.ok()
        }
        function share(text: string): string {
            const value = String(text || "").trim()
            if (!value) return root.fail(I18n.tr("Enter something to share"))
            if (!KdeConnectService.activeReachable) return root.fail(I18n.tr("The phone is not connected"))
            if (/^(https?|file):\/\//i.test(value)) KdeConnectService.shareUrl(value, KdeConnectService.activeDeviceId)
            else KdeConnectService.shareText(KdeConnectService.activeDeviceId, value)
            return root.ok()
        }
        function browse(): string {
            if (!KdeConnectService.activeReachable) return root.fail(I18n.tr("The phone is not connected"))
            KdeConnectService.browseFiles(KdeConnectService.activeDeviceId)
            return root.ok()
        }
        function typeText(text: string): string {
            if (!String(text || "")) return root.fail(I18n.tr("Enter text to type"))
            if (!KdeConnectService.activeReachable) return root.fail(I18n.tr("The phone is not connected"))
            KdeConnectService.sendRemoteText(text)
            return root.ok()
        }
        function dismiss(id: string): string {
            if (!id) return root.fail(I18n.tr("The notification is missing"))
            KdeConnectService.dismissNotification(id)
            return root.ok()
        }
        function dismissAll(): string { KdeConnectService.dismissAllNotifications(); return root.ok() }
        function reply(id: string, text: string): string {
            if (!id || !String(text || "").trim()) return root.fail(I18n.tr("Write a reply first"))
            KdeConnectService.sendReply(id, text)
            return root.ok()
        }
        function action(id: string, key: string): string {
            if (!id || !key) return root.fail(I18n.tr("That notification action is unavailable"))
            KdeConnectService.invokeNotificationAction(id, key)
            return root.ok()
        }
        function runCommand(id: string): string {
            if (!id) return root.fail(I18n.tr("Choose a command first"))
            KdeConnectService.runCommand(id)
            return root.ok()
        }
        function mirrorStart(): string {
            if (KdeConnectService.adbState !== "device")
                return root.fail(I18n.tr("Connect your phone with USB debugging first"))
            PhoneScrcpyService.openMirrorWindow()
            return root.ok()
        }
        function mirrorStop(): string { PhoneScrcpyService.stopMirroring(); return root.ok() }
        function recordStart(): string {
            if (KdeConnectService.adbState !== "device") return root.fail(I18n.tr("Connect your phone with USB debugging first"))
            PhoneScrcpyService.startRecording()
            return root.ok()
        }
        function recordStop(): string { PhoneScrcpyService.stopRecording(); return root.ok() }
        function webcamStart(): string {
            if (KdeConnectService.adbState !== "device") return root.fail(I18n.tr("Connect your phone with USB debugging first"))
            PhoneCameraService.startCamera()
            return root.ok()
        }
        function webcamStop(): string { PhoneCameraService.stopCamera(); return root.ok() }
        function webcamFacing(facing: string): string {
            if (facing !== "front" && facing !== "back") return root.fail(I18n.tr("Camera side must be front or back"))
            PhoneCameraService.setFacing(facing)
            return root.ok()
        }
        function micStart(): string {
            if (KdeConnectService.adbState !== "device") return root.fail(I18n.tr("Connect your phone with USB debugging first"))
            PhoneMicService.startMic()
            return root.ok()
        }
        function micStop(): string { PhoneMicService.stopMic(); return root.ok() }
        function adbRefresh(): string { KdeConnectService._probeAdb(); return root.ok() }
        function adbWifi(): string {
            if (!KdeConnectService.adbWifi()) return root.fail(I18n.tr("Connect the phone by USB and keep KDE Connect online first"))
            return root.ok()
        }
        function adbPair(address: string, code: string): string {
            if (!address || !code) return root.fail(I18n.tr("Enter the pairing address and code"))
            KdeConnectService.adbPair(address, code)
            return root.ok()
        }
        function adbConnect(address: string): string {
            if (!address) return root.fail(I18n.tr("Enter the phone address"))
            KdeConnectService.adbConnect(address)
            return root.ok()
        }
        function contactsRefresh(): string { PhoneContactsService.refresh(); return root.ok() }
        function call(number: string): string {
            if (!String(number || "").trim()) return root.fail(I18n.tr("Enter a phone number"))
            if (KdeConnectService.adbState !== "device") return root.fail(I18n.tr("Connect your phone with USB debugging first"))
            PhoneContactsService.openDialer(number)
            return root.ok()
        }
        function sms(number: string): string {
            if (!String(number || "").trim()) return root.fail(I18n.tr("Enter a phone number"))
            if (KdeConnectService.adbState !== "device") return root.fail(I18n.tr("Connect your phone with USB debugging first"))
            PhoneContactsService.composeSms(number)
            return root.ok()
        }
        function favoriteContact(id: string, on: string): string {
            if (!id || (on !== "true" && on !== "false")) return root.fail(I18n.tr("That contact could not be updated"))
            PhoneState.setFavoriteContact(id, on === "true")
            PhoneContactsService._updateFilteredContacts()
            return root.ok()
        }
        function appsRefresh(): string {
            if (KdeConnectService.adbState !== "device") return root.fail(I18n.tr("Connect your phone with USB debugging first"))
            PhoneScrcpyService.refreshApps()
            return root.ok()
        }
        function appLaunch(packageName: string): string {
            if (!packageName) return root.fail(I18n.tr("Choose an app first"))
            if (KdeConnectService.adbState !== "device") return root.fail(I18n.tr("Connect your phone with USB debugging first"))
            PhoneScrcpyService.launchApp(packageName)
            return root.ok()
        }
        function appStop(packageName: string): string {
            if (!packageName) return root.fail(I18n.tr("Choose an app first"))
            PhoneScrcpyService.stopApp(packageName)
            return root.ok()
        }
        function favoriteApp(packageName: string, on: string): string {
            if (!packageName || (on !== "true" && on !== "false")) return root.fail(I18n.tr("That app could not be updated"))
            PhoneState.setFavoritePackage(packageName, on === "true")
            PhoneScrcpyService._updateFilteredApps()
            return root.ok()
        }
        function callAnswer(): string { PhoneCallService.answer(); return root.ok() }
        function callDecline(): string { PhoneCallService.decline(); return root.ok() }
        function callSilence(): string { PhoneCallService.silence(); return root.ok() }
    }

    Connections {
        target: KdeConnectService
        function onAvailableChanged() { root.queueState() }
        function onReadyChanged() { root.queueState() }
        function onActiveDeviceIdChanged() { root.queueState() }
        function onDevicesChanged() { root.queueState() }
        function onPendingPairRequestsChanged() { root.queueState() }
        function onOutgoingPairIdChanged() { root.queueState() }
        function onNotificationsChanged() { root.queueState() }
        function onRunCommandsChanged() { root.queueState() }
        function onLastErrorChanged() { root.queueState() }
        function onAdbPresentChanged() { root.queueState() }
        function onAdbStateChanged() { root.queueState() }
        function onResolvedAdbSerialChanged() { root.queueState() }
        function onAdbModelChanged() { root.queueState() }
        function onAdbCandidatesChanged() { root.queueState() }
        function onActionFeedback(message, ok) { root.showToast(message, !ok) }
    }
    Connections {
        target: PhoneScrcpyService
        function onAvailableChanged() { root.queueState() }
        function onVersionChanged() { root.queueState() }
        function onMirrorRunningChanged() { root.queueState(); root.writeApps() }
        function onMirrorLaunchingChanged() { root.queueState() }
        function onMirrorLaunchErrorChanged() { root.queueState() }
        function onRecordingRunningChanged() { root.queueState() }
        function onRecordingLaunchingChanged() { root.queueState() }
        function onAppsChanged() {
            root.queueState()
            root.writeApps()
            PhoneAppIconService.fetchMissing(Array.from(PhoneScrcpyService.apps || []).map(app => app.package))
        }
        function onAppsLoadingChanged() { root.queueState() }
        function onAppsErrorChanged() { root.queueState() }
        function onSessionsChanged() { root.queueState(); root.writeApps() }
        function onMirrorFailed(sessionId, title, reason) { root.showToast(reason, true) }
    }
    Connections {
        target: PhoneCameraService
        function onRunningChanged() { root.queueState() }
        function onConnectingChanged() { root.queueState() }
        function onVideoDeviceChanged() { root.queueState() }
        function onFacingChanged() { root.queueState() }
        function onAvailableChanged() { root.queueState() }
        function onLastErrorChanged() { root.queueState() }
        function onErrorOccurred(message) { root.showToast(message, true) }
    }
    Connections {
        target: PhoneMicService
        function onRunningChanged() { root.queueState() }
        function onConnectingChanged() { root.queueState() }
        function onAvailableChanged() { root.queueState() }
        function onLastErrorChanged() { root.queueState() }
        function onErrorOccurred(message) { root.showToast(message, true) }
    }
    Connections {
        target: PhoneContactsService
        function onContactsChanged() { root.queueState(); root.writeContacts() }
        function onReadyChanged() { root.queueState() }
    }
    Connections {
        target: PhoneAppIconService
        function onIconsChanged() { root.writeApps() }
    }
    Connections {
        target: PhoneCallService
        function onCallStateChanged() { root.queueState() }
        function onContactNameChanged() { root.queueState() }
        function onNumberChanged() { root.queueState() }
    }
    Connections {
        target: PhoneAlarmService
        function onNextAtChanged() { root.queueState() }
    }
    Connections {
        target: PhoneState
        function onFavoriteContactIdsChanged() { root.writeContacts() }
        function onFavoritePackagesChanged() { root.writeApps() }
    }

    onEnabledChanged: {
        root.setRuntimeGate()
        root.queueState()
    }

    Component.onCompleted: {
        ensureDir.running = true
        root.refresh()
    }

    Component.onDestruction: {
        PhoneState.runtimeReady = false
    }
}
