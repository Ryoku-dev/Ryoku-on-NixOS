pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import Quickshell.Wayland
import ".."

/**
 * The scrcpy mirror the Phone sidebar shows inside itself.
 *
 * Wayland has no window embedding, so the picture and the touches are carried
 * separately:
 *
 *   • The picture is a `ScreencopyView` of scrcpy's own toplevel, which the
 *     page draws like any other item — rounded, clipped, animated with the
 *     panel. Nothing is copied through main memory and no v4l2 loopback,
 *     kernel module or re-encode is involved.
 *
 *   • The touches are the real thing. The scrcpy window waits off the side of
 *     every monitor and, while the page is settled, is moved to sit exactly
 *     under the picture and pinned there. The panel cuts that rectangle out of
 *     its input region, so a click lands on scrcpy at the very coordinates the
 *     user aimed at, and scrcpy does what it has always done with it —
 *     multi-touch, scrolling, the keyboard, text input, the clipboard. The
 *     window itself is never seen: the panel paints over every pixel of it.
 *
 * The window is only attached while it is fully covered. Anything that can
 * uncover it — a page that is still sliding, a closing sidebar — parks it
 * again first.
 */
Singleton {
    id: root

    // The session manager names windows `ii-phone-<type>-<id>`, and Hyprland's
    // rules for this one match on that title.
    readonly property string sessionId: "embed"
    readonly property string sessionType: "embed"
    readonly property string windowTitle: "ii-phone-" + root.sessionType + "-" + root.sessionId
    /** Where the window waits when nothing is showing it. Far past any real
     *  monitor: a special workspace was the obvious place, but Hyprland pulls
     *  one into view the moment a window is assigned to it and reads no
     *  spelling of the `silent` that would stop it — which put an empty
     *  scratchpad, overlay and all, on screen at every start. */
    readonly property int parkCoordinate: 99000

    // ─── Leases held by the page ──────────────────────────────
    /** The page wants a live picture. Dropping it stops scrcpy after a grace. */
    property bool wanted: false
    /** The page is settled and fully covering `touchRect`, so the window may
     *  be attached underneath it. */
    property bool touchWanted: false
    /** Where the picture is, in the panel surface's own coordinates. The
     *  screen position is worked out from the layer surface itself rather than
     *  from anchors and margins here, because a bar's exclusive zone moves a
     *  layer surface without anything in QML saying so. */
    property rect touchRect: Qt.rect(0, 0, 0, 0)
    property string layerNamespace: ""
    property string screenName: ""
    /** Matched to the frame's corner radius. The window sits exactly under the
     *  frame, so square corners would poke past the rounded picture and smear
     *  through the panel's blur; rounding it is what lets the frame do without
     *  a bezel to hide them behind. */
    property int cornerRadius: 0

    // ─── Session state ────────────────────────────────────────
    readonly property bool running: PhoneScrcpyService.embedRunning
    readonly property bool launching: PhoneScrcpyService.embedLaunching
    readonly property string lastError: PhoneScrcpyService.embedError
    readonly property bool available: PhoneScrcpyService.available && KdeConnectService.adbReachable

    /** scrcpy's window, once it exists. The loop reads every title, so the
     *  binding re-runs when one changes rather than only when the list does. */
    readonly property Toplevel toplevel: {
        const list = ToplevelManager.toplevels?.values ?? [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].title === root.windowTitle)
                return list[i];
        }
        return null;
    }

    /** True once the window is sitting under `touchRect` and taking input. */
    property bool attached: false

    // ─── Phone geometry ───────────────────────────────────────
    property int deviceWidth: 0
    property int deviceHeight: 0
    /** Falls back to a 20:9 phone until the real size comes back, so the
     *  frame never has to jump once it does. */
    readonly property real deviceAspect: (deviceWidth > 0 && deviceHeight > 0)
        ? (deviceWidth / deviceHeight)
        : (9 / 20)

    // ─── Session lifecycle ────────────────────────────────────

    /** How long a mirror stays up after its page goes away. The sidebar drops
     *  its content aggressively once closed, so without this every trip back
     *  to the Phone tab paid for a fresh connection; the phone keeps encoding
     *  for that long, which is why it is bounded and configurable. */
    readonly property int keepWarmMs: Math.max(0,
        Config.options?.phone?.scrcpy?.embed?.keepWarmSeconds ?? 120) * 1000

    Timer {
        id: stopGrace
        interval: Math.max(1000, root.keepWarmMs)
        repeat: false
        onTriggered: if (!root.wanted) root._stopNow()
    }

    onWantedChanged: {
        if (root.wanted) {
            stopGrace.stop();
            root._start();
        } else {
            launchDebounce.stop();
            startFallback.stop();
            root.touchWanted = false;
            if (root.running || root.launching)
                stopGrace.restart();
        }
    }

    // The encoder is sized from the frame, so starting before the page has
    // measured itself asks the phone for a stream that is then scaled up to
    // fill a frame it was never meant for.
    function _start(): void {
        if (root.running || root.launching) {
            // Already up: only the placement can be stale.
            root._schedulePlacement();
            return;
        }
        // Even a measured frame is still growing into place on the way in,
        // and the encoder is sized once: what it wants is the rectangle the
        // frame comes to rest on, not the first one it reports.
        launchDebounce.restart();
        startFallback.restart();
    }

    Timer {
        id: launchDebounce
        interval: 220
        repeat: false
        onTriggered: {
            if (!root.wanted || root.running || root.launching)
                return;
            if (root.touchRect.height <= 0)
                return;
            root._launchNow();
        }
    }

    function _launchNow(): void {
        launchDebounce.stop();
        startFallback.stop();
        // A mirror this engine never asked for is one kept warm across a
        // config reload: the shell has no way to take the old session over,
        // and starting beside it would leave two scrcpy windows fighting for
        // the same frame.
        if (root.toplevel && !root.running) {
            PhoneScrcpyService.stopEmbed();
            root.toplevel.close();
        }
        root._probeDeviceSize();
        PhoneScrcpyService.launchEmbed(root._streamSize());
    }

    // A frame that never reports a size must not mean a mirror that never
    // opens; the floor in _streamSize() covers what it is started with.
    Timer {
        id: startFallback
        interval: 600
        repeat: false
        onTriggered: if (root.wanted && !root.running && !root.launching) root._launchNow()
    }

    // The manager outlives a config reload with this session still running,
    // and the shell that comes back has no memory of it. Saying so repeatedly
    // is what makes "nobody is asking for it any more" something the manager
    // can notice at all.
    Timer {
        id: keepalive
        interval: 5000
        repeat: true
        // Also while the session is only being kept warm: the manager drops
        // anything that stops asking for itself, page or no page.
        running: root.running && (root.wanted || stopGrace.running)
        triggeredOnStart: true
        onTriggered: PhoneScrcpyService.keepEmbedAlive()
    }

    // A config reload takes this singleton down while the window is still
    // attached — and the panel that was covering it goes with it, so for the
    // moment before the next engine notices the stray, it would simply be a
    // scrcpy window sitting on the desktop. Parking it first is cheap.
    Component.onDestruction: root._park()

    function _stopNow(): void {
        root._park();
        PhoneScrcpyService.stopEmbed();
        root.attached = false;
    }

    /** The encoded stream is capped to what the panel actually shows: a phone
     *  streaming 1080x2340 into a 400-pixel-wide frame spends the whole budget
     *  on pixels that are thrown away at the first scale. */
    function _streamSize(): int {
        // scrcpy caps the longer side, which is the height for a phone held
        // upright and the width once it is turned over.
        const side = Math.round(Math.max(root.touchRect.width, root.touchRect.height));
        if (side <= 0)
            return 1024;
        return Math.max(480, Math.min(1440, Math.round(side * root._screenScale())));
    }

    function _screenScale(): real {
        const wanted = String(root.screenName || "");
        const screens = Quickshell.screens ?? [];
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === wanted)
                return Math.max(1, Math.min(2, screens[i].devicePixelRatio || 1));
        }
        return 1;
    }

    // ─── Placement ────────────────────────────────────────────

    // Geometry arrives as a stream while the panel resizes or the page
    // settles; Hyprland only needs the value it comes to rest on.
    Timer {
        id: placementDebounce
        interval: 60
        repeat: false
        onTriggered: root._applyPlacement()
    }

    function _schedulePlacement(): void {
        placementDebounce.restart();
    }

    onTouchRectChanged: {
        root._schedulePlacement();
        // Every change pushes the launch back, so it lands on the size the
        // frame settles at rather than on one it passes through.
        if (root.wanted && !root.running && !root.launching)
            launchDebounce.restart();
    }
    onTouchWantedChanged: root._schedulePlacement()
    onCornerRadiusChanged: {
        root._placedAttached = false;
        root._schedulePlacement();
    }
    onToplevelChanged: {
        if (root.toplevel) {
            root._schedulePlacement();
            if (!root.wanted)
                strayCheck.restart();
        } else {
            root.attached = false;
            strayCheck.stop();
        }
    }

    // A config reload hands the session manager, and every scrcpy under it,
    // to the new engine — but nothing here remembers having asked for one.
    // Every other session type has a window the user can close; this one is
    // invisible by design, so left behind it would keep the phone encoding
    // video for nobody. The delay is only there to let an ordinary launch
    // claim its own window first.
    Timer {
        id: strayCheck
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.wanted || root.running || root.launching || !root.toplevel)
                return;
            // Told to the manager for its bookkeeping, and asked of the window
            // itself in case this engine inherited neither.
            PhoneScrcpyService.stopEmbed();
            root.toplevel.close();
        }
    }

    // The seam's embed path: where the compositor can pin a window under a
    // layer surface, this carries the placement and the layout-churn signal;
    // elsewhere `available` is false and the session shows as a plain window.
    WindowEmbed {
        id: embed
        title: root.windowTitle
        layerNamespace: root.layerNamespace
        cornerRadius: root.cornerRadius
        parkCoordinate: root.parkCoordinate
        onLayoutChanged: {
            root._placedAttached = false;
            root._schedulePlacement();
        }
    }

    // What was last sent, so an unchanged rectangle never becomes an IPC call.
    property rect _placedRect: Qt.rect(0, 0, 0, 0)
    property bool _placedAttached: false

    function _applyPlacement(): void {
        if (!root.toplevel)
            return;

        if (!root.touchWanted || !root.wanted) {
            root._park();
            return;
        }

        const r = root.touchRect;
        const rw = Math.round(r.width);
        const rh = Math.round(r.height);
        const rx = Math.round(r.x);
        const ry = Math.round(r.y);
        if (rw < 16 || rh < 16)
            return;

        if (root._placedAttached
            && root._placedRect.x === rx && root._placedRect.y === ry
            && root._placedRect.width === rw && root._placedRect.height === rh)
            return;

        if (!embed.available)
            return;
        embed.x0 = rx;
        embed.y0 = ry;
        embed.width0 = rw;
        embed.height0 = rh;
        embed.embed();

        root._placedRect = Qt.rect(rx, ry, rw, rh);
        root._placedAttached = true;
        root.attached = true;
    }

    /** Puts the window back on the rectangle the frame is asking for, after
     *  something outside the shell has moved or resized it. The phone's size
     *  is re-read at the same time, so a handset that was turned over ends up
     *  with a frame that follows it rather than one that fights it. */
    function reassertGeometry(): void {
        root._probeDeviceSize();
        root._placedAttached = false;
        root._schedulePlacement();
    }

    function _park(): void {
        if (!root._placedAttached)
            return;
        root._placedAttached = false;
        root._placedRect = Qt.rect(0, 0, 0, 0);
        root.attached = false;
        if (!root.toplevel || !embed.available)
            return;
        embed.park();
    }

    // ─── Phone keys ───────────────────────────────────────────
    // One-shot and rare, so the ~120 ms `adb shell input` costs is invisible
    // next to keeping a shell open on the phone for the whole session.
    function sendKey(keycode: string): void {
        if (!keycode || !KdeConnectService.adbReachable)
            return;
        Quickshell.execDetached(["adb"]
            .concat(KdeConnectService.adbTargetArgs())
            .concat(["shell", "input", "keyevent", keycode]));
    }

    function goHome(): void { root.sendKey("KEYCODE_HOME"); }
    function goBack(): void { root.sendKey("KEYCODE_BACK"); }
    function goRecents(): void { root.sendKey("KEYCODE_APP_SWITCH"); }
    function togglePower(): void { root.sendKey("KEYCODE_POWER"); }
    function volumeUp(): void { root.sendKey("KEYCODE_VOLUME_UP"); }
    function volumeDown(): void { root.sendKey("KEYCODE_VOLUME_DOWN"); }
    function openNotifications(): void {
        if (!KdeConnectService.adbReachable)
            return;
        Quickshell.execDetached(["adb"]
            .concat(KdeConnectService.adbTargetArgs())
            .concat(["shell", "cmd", "statusbar", "expand-notifications"]));
    }

    /** Hands the session over to a normal scrcpy window, for when the sidebar
     *  is too small for what is on screen. The page closes itself after this,
     *  which is what releases the embedded session. */
    function detachToWindow(): void {
        PhoneScrcpyService.openMirrorWindow();
    }

    /** Ends the embedded session now instead of keeping it warm: the phone
     *  is being mirrored somewhere else, or not at all any more. */
    function release(): void {
        launchDebounce.stop();
        startFallback.stop();
        stopGrace.stop();
        root.touchWanted = false;
        if (root.running || root.launching || root.toplevel)
            root._stopNow();
    }

    // ─── Phone resolution ─────────────────────────────────────
    // Read once per session: the frame has to have the phone's aspect ratio
    // exactly, or scrcpy letterboxes inside a window the panel drew to fit.
    Process {
        id: deviceSizeProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                // "Physical size: 1080x2340", plus an "Override size:" line
                // when one is set — the override is what is on screen.
                const found = this.text.match(/(\d+)x(\d+)/g);
                if (!found || found.length === 0)
                    return;
                const last = found[found.length - 1].split("x");
                root.deviceWidth = parseInt(last[0]) || 0;
                root.deviceHeight = parseInt(last[1]) || 0;
            }
        }
    }

    function _probeDeviceSize(): void {
        if (!KdeConnectService.adbReachable)
            return;
        deviceSizeProc.running = false;
        deviceSizeProc.command = ["adb"]
            .concat(KdeConnectService.adbTargetArgs())
            .concat(["shell", "wm", "size"]);
        deviceSizeProc.running = true;
    }

    // A phone that rotates changes the aspect the frame has to keep.
    Connections {
        target: PhoneScrcpyService
        ignoreUnknownSignals: true
        function onEmbedRunningChanged(): void {
            if (PhoneScrcpyService.embedRunning) {
                root._probeDeviceSize();
                root._placedAttached = false;
                root._schedulePlacement();
            } else {
                root.attached = false;
                root._placedAttached = false;
            }
        }
    }
}
