pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import shell.services

/**
 * Launcher icons for the Android apps listed in the phone panel.
 *
 * Android has no way to hand an icon to the desktop, so a helper resolves each
 * one out of the installed APK over adb. It starts only when an icon lookup
 * needs the disk cache or an explicit app-list refresh requests missing icons,
 * then exits after the request queue has been idle. Extracted icons remain
 * cached on disk across shell restarts and device reconnects.
 */
Singleton {
    id: root

    readonly property bool enabled: PhoneState.runtimeReady
        && KdeConnectService.available
        && (Config.phone?.scrcpy?.appMode?.showAppIcons ?? true)
    readonly property string deviceId: KdeConnectService.activeDeviceId || "default"

    // package name -> icon file path, "" for apps whose icon cannot be resolved
    property var icons: ({})
    property bool available: true
    property string unavailableReason: ""

    readonly property var pending: new Set()
    // Progress of the running fetch, so the panel can show something meanwhile
    property int outstanding: 0
    property int batchSize: 0
    readonly property bool fetching: root.outstanding > 0
    readonly property int fetched: root.batchSize - root.outstanding
    property var queuedMessages: []
    property string cacheRequestedFor: ""

    function iconFor(packageName: string): string {
        if (packageName && root.enabled && root.cacheRequestedFor !== root.deviceId)
            root.loadCached();
        return root.icons[packageName] ?? "";
    }

    /**
     * Pull the icons of every listed app that has none yet. Only ever called
     * from a user-initiated refresh — nothing here reacts to the phone coming
     * back on its own.
     */
    function fetchMissing(packages: var): void {
        if (!root.enabled || !root.available) return;
        if (!KdeConnectService.adbReachable) return;

        const wanted = Array.from(packages ?? []).filter(name => name && !root.icons[name] && !root.pending.has(name));
        if (wanted.length === 0) return;

        wanted.forEach(name => {
            root.pending.add(name);
            root._sendToDevice({
                "cmd": "fetch",
                "package": name,
                "deviceId": root.deviceId
            });
        });
        root.batchSize += wanted.length;
        root.outstanding = root.pending.size;
    }

    function loadCached(): void {
        if (!root.enabled || root.cacheRequestedFor === root.deviceId)
            return;
        root.cacheRequestedFor = root.deviceId;
        root._enqueue({
            "cmd": "cached",
            "deviceId": root.deviceId
        });
    }

    /** Throw away every extracted icon, so the next refresh re-reads them all. */
    function clearCache(): void {
        root.icons = ({});
        root._resetProgress();
        root.cacheRequestedFor = root.enabled ? root.deviceId : "";
        root._enqueue({
            "cmd": "clear",
            "deviceId": root.deviceId
        });
    }

    function _enqueue(message: var): void {
        if (!root.enabled || !root.available)
            return;
        root.queuedMessages = root.queuedMessages.concat([message]);
        iconIdle.stop();
        if (!iconProc.running)
            iconProc.running = true;
        else if (iconProc.processId)
            root._flush();
    }

    function _flush(): void {
        if (!iconProc.running || !iconProc.processId || root.queuedMessages.length === 0)
            return;
        const queued = root.queuedMessages;
        root.queuedMessages = [];
        for (let i = 0; i < queued.length; i++)
            iconProc.write(JSON.stringify(queued[i]) + "\n");
        root._armIdle();
    }

    function _armIdle(): void {
        if (iconProc.running && root.outstanding === 0 && root.queuedMessages.length === 0)
            iconIdle.restart();
        else
            iconIdle.stop();
    }

    function _sendToDevice(message: var): void {
        if (!root.enabled || !root.available)
            return;
        KdeConnectService.withAdbTarget(args => {
            if (!root.enabled || !root.available)
                return;
            message.target_args = args || [];
            root._enqueue(message);
        });
    }

    function _resetProgress(): void {
        root.pending.clear();
        root.outstanding = 0;
        root.batchSize = 0;
    }

    function _settle(packageName: string): void {
        root.pending.delete(packageName);
        root.outstanding = root.pending.size;
        if (root.outstanding === 0) root.batchSize = 0;
        root._armIdle();
    }

    function _store(packageName: string, path: string): void {
        root._settle(packageName);
        // Reassign rather than mutate so bindings on the map re-evaluate.
        const next = Object.assign({}, root.icons);
        next[packageName] = path;
        root.icons = next;
    }

    onDeviceIdChanged: {
        iconIdle.stop();
        iconProc.running = false;
        root.queuedMessages = [];
        root.icons = ({});
        root.cacheRequestedFor = "";
        root._resetProgress();
    }

    onEnabledChanged: {
        if (root.enabled)
            return;
        iconIdle.stop();
        iconProc.running = false;
        root.queuedMessages = [];
        root._resetProgress();
    }

    Timer {
        id: iconIdle
        interval: 15000
        repeat: false
        onTriggered: iconProc.running = false
    }

    Process {
        id: iconProc
        stdinEnabled: true
        command: PhoneState.pdeath(["python3", Quickshell.shellPath("modules/phone/scripts/phone/android_icon_extractor.py")])
        running: false
        onStarted: root._flush()
        onExited: {
            root.queuedMessages = [];
            if (root.outstanding > 0)
                root._resetProgress();
        }

        stdout: SplitParser {
            onRead: data => {
                try {
                    const msg = JSON.parse(data);
                    if (msg.event === "icon") {
                        // A retry means the phone went away mid-fetch, not that the app
                        // has no icon — leave it unresolved so the next refresh picks it
                        // up again instead of remembering the failure.
                        if (msg.retry) root._settle(msg.package);
                        else root._store(msg.package, msg.path || "");
                    } else if (msg.event === "cached") {
                        root.icons = Object.assign({}, root.icons, msg.icons || {});
                        root._armIdle();
                    } else if (msg.event === "cleared") {
                        root.icons = ({});
                        root._armIdle();
                    } else if (msg.event === "unavailable") {
                        root.available = false;
                        root.unavailableReason = msg.reason || "";
                        console.warn("[PhoneAppIconService] icons disabled:", root.unavailableReason);
                        root._armIdle();
                    }
                } catch (e) {
                    console.warn("[PhoneAppIconService] JSON error:", e, "Data:", data);
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) console.warn("[PhoneAppIconService stderr]", data);
            }
        }
    }
}
