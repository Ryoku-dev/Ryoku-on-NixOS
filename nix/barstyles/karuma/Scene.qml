pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Ryoku.Ui.Singletons
import Ryoku.PluginKit
import shell.services as Shell
import "KarumaData.js" as HD
import "KarumaSchema.js" as Schema
import "Calendar.js" as Cal
import "."

/*
 * Karuma (a Ryoku bar style inspired by the original Ma layout)
 *
 * Native Ryoku BarProducts Scene entry point. Frame loads a Scene per monitor;
 * one primary Scene owns the shared state and instantiates the real bar window
 * for each output, avoiding duplicate global services and duplicate pop-outs.
 *
 * The strip itself (BarSurface.qml) uses the original "Ma" paper-and-ink layout: kanji
 * workspaces, serif clock, underlined media, 波 双 耳 光 充 readings, stamps and
 * the day rod. Colours follow Matugen exactly like Ricelin (KarumaPalette.qml).
 */
Item {
    id: root

    property var modelData: null
    property string sheet: ""
    property string sheetScreen: ""
    property date now: new Date()
    property int mediaPulse: 0
    // Native Ryoku plugin panel state. The glyph owns its pluginApi; Scene only
    // carries that handle into Karuma's shared paper sheet.
    property string pluginPanelId: ""
    property var pluginPanelApi: null

    // Network (nmcli): kind wifi | ethernet | disconnected
    property var netInfo: ({ kind: "disconnected", name: "Offline", bars: 0, off: true, needsYou: true })
    // Bluetooth: null when there is no adapter
    property var btInfo: null
    property bool backlightPresent: false
    property int backlightPct: 0
    property bool recording: false
    property bool keepAwake: false
    // Karuma's configuration hub (KarumaHub.qml), owned by the primary Scene.
    property bool hubOpen: false
    // Wi-Fi radio (nmcli): true / false, or null when NetworkManager does not say.
    property var wifiRadio: null
    // The newest brightness the quick settings slider asked for, not yet sent (-1: none).
    property int pendingBrightness: -1

    readonly property string activeConnection: netInfo.name
    readonly property bool bluetoothPowered: !!btInfo && btInfo.enabled

    // Only outputs that actually request Karuma participate in its shared host.
    // This respects Ryoku's per-display bar visibility/style settings and also
    // lets Karuma live on a non-primary monitor without needing frame-family
    // special casing in the shell loader.
    readonly property var barScreens: {
        const screens = Quickshell.screens || [];
        const out = [];
        for (let i = 0; i < screens.length; ++i) {
            const screen = screens[i];
            if (!screen || !screen.name)
                continue;
            if (!Tokens.barEnabledFor(screen.name))
                continue;
            if (Shell.Config.barStyleFor(screen.name) !== "karuma")
                continue;
            out.push(screen);
        }
        return out;
    }

    readonly property bool isPrimary: root.barScreens.length > 0
        && !!root.modelData
        && root.barScreens[0].name === root.modelData.name

    // ------------------------------------------------------------ audio / power
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property real volume: sink && sink.audio ? Math.max(0, Math.min(1, sink.audio.volume)) : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.ready && battery.isLaptopBattery && battery.isPresent
    readonly property int batteryPercent: hasBattery ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

    readonly property var volumeInfo: sink && sink.audio
        ? { percent: Math.round(Math.max(0, sink.audio.volume) * 100), level: volume, muted: muted, needsYou: muted }
        : null
    readonly property var batteryInfo: hasBattery
        ? { percent: batteryPercent, level: batteryPercent / 100, charging: charging, needsYou: !charging && batteryPercent <= 15 }
        : null
    readonly property var brightnessInfo: backlightPresent
        ? { percent: backlightPct, level: backlightPct / 100 }
        : null

    // What the quick settings menu shows; null hides a control the machine does not have.
    readonly property var micInfo: source && source.audio ? { muted: !!source.audio.muted } : null
    readonly property var wifiInfo: wifiRadio === null ? null
        : { on: wifiRadio, name: netInfo.kind === "wifi" ? String(netInfo.name) : "" }
    readonly property var bluetoothInfo: btInfo ? { on: !!btInfo.enabled, name: btInfo.connected ? String(btInfo.name) : "" } : null

    // ------------------------------------------------------------ media
    readonly property var activePlayer: {
        void root.mediaPulse;
        const all = Mpris.players.values;
        for (let i = 0; i < all.length; ++i) {
            const p = all[i];
            if (!p || String(p.dbusName || "").toLowerCase().indexOf("playerctld") >= 0)
                continue;
            if (p.isPlaying && (p.trackTitle || p.trackArtist))
                return p;
        }
        for (let j = 0; j < all.length; ++j) {
            const p = all[j];
            if (p && String(p.dbusName || "").toLowerCase().indexOf("playerctld") < 0 && (p.trackTitle || p.trackArtist))
                return p;
        }
        return null;
    }

    readonly property string mediaTitle: activePlayer
        ? String(activePlayer.trackTitle || activePlayer.identity || "Now playing") : "Nothing playing"
    readonly property string mediaArtist: {
        if (!activePlayer) return "MPRIS · idle";
        const a = activePlayer.trackArtists;
        if (a && typeof a.join === "function" && a.length > 0) return a.join(", ");
        if (a && String(a).length > 0) return String(a);
        return String(activePlayer.trackArtist || activePlayer.identity || "Media player");
    }

    readonly property var mediaInfo: {
        const p = root.activePlayer;
        if (!p) return null;
        const len = Number(p.length) || 0;
        const pos = Number(p.position) || 0;
        return {
            title: root.mediaTitle,
            artist: root.mediaArtist === "MPRIS · idle" ? "" : root.mediaArtist,
            progress: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0,
            // Streams and some players report no length; the under-bar line then has nothing to follow.
            hasLength: len > 0,
            playing: !!p.isPlaying
        };
    }

    // ------------------------------------------------------------ notifications
    // Newest first; the shell's own notification server owns the list.
    readonly property var notifList: {
        const out = [];
        const t = Shell.Notifs.tracked || [];
        for (let i = t.length - 1; i >= 0; --i) {
            const n = t[i];
            if (!n) continue;
            const app = String(n.appName || "");
            out.push({
                // The same identity the tilt uses, so a stamp keeps its place while others come and go.
                key: String(n.id !== undefined ? n.id : "i" + i) + "|" + app,
                app: app.length ? app : "System",
                summary: String(n.summary || ""),
                urgent: n.urgency === 2,
                glyph: HD.stampGlyph(app),
                tilt: HD.tilt(app + "|" + (n.id !== undefined ? n.id : i) + "|" + (n.summary || ""))
            });
        }
        return out;
    }

    // ------------------------------------------------------------ indicators
    readonly property var indicatorList: {
        const all = [
            { key: "record", glyph: "写", title: "Recording", on: root.recording, red: true },
            { key: "awake", glyph: "目", title: "Stay awake", on: root.keepAwake, red: false }
        ];
        return hp.allIndicators ? all : all.filter(function(i) { return i.on; });
    }

    // ------------------------------------------------------------ window
    readonly property var focusedWindow: Wm.focusedWindow
    readonly property string focusedTitle: {
        const w = root.focusedWindow;
        if (!w) return "No active window";
        return String(w.title || w.appId || w.class || w.app_id || "Untitled window");
    }
    readonly property string focusedClass: {
        const w = root.focusedWindow;
        return w ? String(w.appId || w.class || w.app_id || "") : "";
    }
    readonly property string focusedRawTitle: {
        const w = root.focusedWindow;
        return w ? String(w.title || "") : "";
    }

    function toggleHub() { root.hubOpen = !root.hubOpen; }

    // Removes every waiting notification from the shell's own list, so the
    // stamps and the count empty out. Uses the service's own "clear all" when
    // it has one, otherwise dismisses each tracked notification one by one.
    function clearNotifications() {
        const svc = Shell.Notifs;
        if (!svc) return;
        const bulk = ["clearAll", "dismissAll", "clear"];
        for (let i = 0; i < bulk.length; ++i) {
            if (typeof svc[bulk[i]] === "function") {
                svc[bulk[i]]();
                return;
            }
        }
        const tracked = svc.tracked || [];
        const all = [];
        for (let j = 0; j < tracked.length; ++j)
            if (tracked[j]) all.push(tracked[j]);
        for (let k = 0; k < all.length; ++k) {
            const n = all[k];
            if (typeof n.dismiss === "function") n.dismiss();
            else if (typeof n.close === "function") n.close();
        }
    }

    function openSheet(key, screenName) {
        const name = screenName || Wm.focusedOutput || (Quickshell.screens.length ? Quickshell.screens[0].name : "");
        if (root.sheet === key && root.sheetScreen === name) {
            root.closeSheet();
            return;
        }
        root.sheet = key;
        root.sheetScreen = name;
    }

    function closeSheet() {
        const wasPlugin = root.sheet === "plugin"
        root.sheet = "";
        root.sheetScreen = "";
        if (wasPlugin) {
            root.pluginPanelId = ""
            root.pluginPanelApi = null
        }
    }

    function toggleSheet(key, screenName) {
        root.openSheet(key, screenName);
    }

    function openPluginPanel(id, api, screenName) {
        id = String(id || "")
        if (!id.length) {
            root.pluginPanelId = ""
            root.pluginPanelApi = null
            if (root.sheet === "plugin") root.closeSheet()
            return
        }
        if (root.sheet === "plugin" && root.pluginPanelId === id
                && (!screenName || root.sheetScreen === screenName)) {
            root.closeSheet()
            root.pluginPanelId = ""
            root.pluginPanelApi = null
            return
        }
        root.pluginPanelId = id
        root.pluginPanelApi = api
        root.openSheet("plugin", screenName)
    }

    function pluginEntry(id) { return karumaPlugins.entryFor(String(id || "")) }

    // One stable identity per workspace, the same on every compositor (and the
    // same one Ricelin's strip uses): Hyprland names a workspace after its
    // numeric id; niri workspaces are usually unnamed and are known by their
    // per-output position (idx) or global id. Named workspaces fall back to
    // that number, so rows, the active marker and click targets always agree.
    function workspaceIdentity(w) {
        if (!w) return "";
        const name = parseInt(String(w.name), 10);
        if (!isNaN(name) && name >= 1) return String(name);
        const idx = parseInt(String(w.idx), 10);
        if (!isNaN(idx) && idx >= 1) return String(idx);
        // A named, un-indexed workspace (Hyprland "name:foo") keeps its name.
        if (w.name !== undefined && w.name !== null && String(w.name).length > 0 && String(w.name) !== "null"
            && (w.idx === undefined || w.idx === null))
            return String(w.name);
        const id = parseInt(String(w.id), 10);
        if (!isNaN(id) && id >= 1) return String(id);
        return "";
    }

    function workspaceSortKey(w) {
        const n = parseInt(root.workspaceIdentity(w), 10);
        return isNaN(n) ? 100000 : n;
    }

    // How many windows sit on a workspace; 0 when the WM API doesn't say.
    function windowCount(ws) {
        if (!ws) return 0;
        let n = 0;
        try {
            const wins = Wm.windows || [];
            for (let i = 0; i < wins.length; ++i) {
                const v = wins[i] ? String(wins[i].workspace) : "";
                if (v.length && (v === String(ws.name) || v === String(ws.id)))
                    n++;
            }
        } catch (e) {
            return 0;
        }
        return n;
    }

    function workspaceRowsFor(screenName) {
        void Wm.workspaces;
        void Wm.windows;
        const rows = [];
        const seen = ({});
        const list = Wm.workspaces || [];
        for (let i = 0; i < list.length; ++i) {
            const w = list[i];
            if (!w || w.special === true || String(w.output || "") !== String(screenName || "")) continue;
            const id = root.workspaceIdentity(w);
            if (!id.length || seen[id]) continue;
            seen[id] = true;
            rows.push({ id: id, label: root.workspaceLabel(id), count: root.windowCount(w), ws: w });
        }
        const active = root.activeWorkspaceFor(screenName);
        if (active.length && !seen[active]) {
            seen[active] = true;
            rows.push({ id: active, label: root.workspaceLabel(active), count: 0, ws: null });
        }
        // Like upstream, pages 1..5 are always there (numbered workspaces only).
        let numbered = true;
        for (let r = 0; r < rows.length; ++r)
            if (isNaN(parseInt(rows[r].id, 10))) numbered = false;
        if (numbered) {
            for (let n = 1; n <= 5; ++n) {
                const id = String(n);
                if (!seen[id]) {
                    seen[id] = true;
                    rows.push({ id: id, label: root.workspaceLabel(id), count: 0, ws: null });
                }
            }
        }
        rows.sort(function(a, b) {
            const ka = parseInt(a.id, 10), kb = parseInt(b.id, 10);
            const na = isNaN(ka) ? 100000 : ka, nb = isNaN(kb) ? 100000 : kb;
            return na === nb ? a.id.localeCompare(b.id) : na - nb;
        });
        return rows;
    }

    function workspaceLabel(name) {
        const n = parseInt(String(name), 10);
        if (!isNaN(n) && n >= 1 && n <= 10) return HD.numeral(n);
        const s = String(name || "?");
        return s.length > 2 ? s.slice(0, 2) : s;
    }

    // The live workspace on one output. Same order as Ricelin: an explicit
    // active/focused flag on the workspace entries first (niri reports one per
    // output), then the output's activeWorkspace matched against each entry's
    // name, idx or id, so unnamed niri workspaces resolve to the same identity
    // the rows use.
    function activeWorkspaceFor(screenName) {
        const list = Wm.workspaces || [];
        void Wm.focusedWorkspace;
        void Wm.focusedOutput;
        for (let i = 0; i < list.length; ++i) {
            const w = list[i];
            if (!w || w.special === true || String(w.output || "") !== String(screenName || "")) continue;
            if (w.active === true || w.focused === true || w.isActive === true || w.isFocused === true)
                return root.workspaceIdentity(w);
        }

        const output = Wm.outputByName(screenName);
        const aw = output ? output.activeWorkspace : null;
        if (aw && typeof aw === "object") return root.workspaceIdentity(aw);
        if (aw !== null && aw !== undefined && String(aw).length) {
            const awStr = String(aw);
            for (let j = 0; j < list.length; ++j) {
                const w = list[j];
                if (!w || w.special === true || String(w.output || "") !== String(screenName || "")) continue;
                if (String(w.name) === awStr || String(w.idx) === awStr || String(w.id) === awStr)
                    return root.workspaceIdentity(w);
            }
            const n = parseInt(awStr, 10);
            return isNaN(n) ? awStr : String(n);
        }

        const focused = Wm.focusedWorkspace;
        if (Wm.focusedOutput === screenName && focused) return root.workspaceIdentity(focused);
        return "";
    }

    function stepWorkspace(screenName, delta) {
        const rows = root.workspaceRowsFor(screenName);
        if (!rows.length) return;
        const active = root.activeWorkspaceFor(screenName);
        let at = 0;
        for (let i = 0; i < rows.length; ++i)
            if (rows[i].id === active) { at = i; break; }
        at = Math.max(0, Math.min(rows.length - 1, at + delta));
        Wm.focusWorkspace(String(rows[at].id));
    }

    function setVolume(value) {
        if (root.sink && root.sink.audio)
            root.sink.audio.volume = Math.max(0, Math.min(1, Number(value)));
    }

    function nudgeVolume(delta) {
        if (root.sink && root.sink.audio)
            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + delta));
    }

    function toggleMute() {
        if (root.sink && root.sink.audio)
            root.sink.audio.muted = !root.sink.audio.muted;
    }

    function mediaAction(action) {
        const p = root.activePlayer;
        if (!p) return;
        if (action === "previous" && p.canGoPrevious) p.previous();
        else if (action === "playPause" && p.canTogglePlaying) p.togglePlaying();
        else if (action === "next" && p.canGoNext) p.next();
    }

    function toggleMic() {
        if (root.source && root.source.audio)
            root.source.audio.muted = !root.source.audio.muted;
    }

    // The slider calls this on every drag step; only the latest value is sent, at most
    // once per tick, so a drag is a stream of brightnessctl calls rather than a flood.
    function setBrightness(percent) {
        root.pendingBrightness = Math.max(1, Math.min(100, Math.round(Number(percent))));
        if (!brightTimer.running) brightTimer.start();
    }

    function toggleWifi() {
        if (root.wifiRadio === null) return;
        const next = !root.wifiRadio;
        Quickshell.execDetached(["nmcli", "radio", "wifi", next ? "on" : "off"]);
        // Shown at once; the probe a moment later confirms what NetworkManager really did.
        root.wifiRadio = next;
        wifiRefresh.restart();
    }

    // Re-read what the quick settings menu shows (the slower probes normally wait 15 s).
    function refreshQuick() {
        if (!root.isPrimary) return;
        if (!wifiProbe.running) wifiProbe.running = true;
        if (!netProbe.running) netProbe.running = true;
        if (!btProbe.running) btProbe.running = true;
    }

    onSheetChanged: { if (root.sheet === "quick") root.refreshQuick(); }

    function toggleBluetooth() {
        Quickshell.execDetached(["bluetoothctl", "power", root.bluetoothPowered ? "off" : "on"]);
        btRefresh.restart();
    }

    function toggleRecording() {
        if (root.recording) {
            Quickshell.execDetached(["pkill", "-SIGINT", "-x", "gpu-screen-recorder"]);
        } else {
            Quickshell.execDetached(["sh", "-c",
                "d=\"$HOME/Videos/Recordings\"; mkdir -p \"$d\"; exec gpu-screen-recorder -w screen -f 60 -a default_output -o \"$d/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4\""]);
        }
        recRefresh.restart();
    }

    function statusAction(name, how, screenName) {
        if (name === "volume") {
            if (how === "right" || how === "middle") root.toggleMute();
            else if (how === "up") root.nudgeVolume(0.02);
            else if (how === "down") root.nudgeVolume(-0.02);
            else root.toggleSheet("sound", screenName);
        } else if (name === "network") {
            root.toggleSheet("network", screenName);
        } else if (name === "bluetooth") {
            if (how === "click") root.toggleBluetooth();
        } else if (name === "battery") {
            root.toggleSheet("power", screenName);
        } else if (name === "brightness") {
            if (how === "up") Quickshell.execDetached(["brightnessctl", "set", "2%+"]);
            else if (how === "down") Quickshell.execDetached(["brightnessctl", "set", "2%-"]);
        }
    }

    function stateLabel() {
        if (!root.hasBattery) return "Desktop · AC power";
        if (root.charging) return "Charging · " + root.batteryPercent + "%";
        if (root.battery.state === UPowerDeviceState.FullyCharged) return "Fully charged · " + root.batteryPercent + "%";
        if (root.battery.state === UPowerDeviceState.Discharging) return "Discharging · " + root.batteryPercent + "%";
        return "Battery state · " + root.batteryPercent + "%";
    }

    // Hide against the focused window's actual toplevel state, and also cover
    // borderless/windowed-fullscreen applications whose toplevel does not report
    // fullscreen. The reserved strip itself remains mapped, so tiling geometry
    // cannot jump when the bar is hidden or restored.
    // Bumped by a short re-check timer while a bar is hidden, so a stale
    // "fullscreen" answer can never keep Karuma hidden indefinitely.
    property int fullscreenRecheck: 0

    // True only when the window is positively known to live on a workspace that
    // is not the active one of this output. Some compositors (niri) keep the
    // last focused window around after switching to an empty workspace; that
    // stale window may still report fullscreen. Unknown = false (never guess).
    function windowOnInactiveWorkspace(win, screenName) {
        const wsVal = win && win.workspace !== undefined && win.workspace !== null ? String(win.workspace) : "";
        if (!wsVal.length)
            return false;
        const list = Wm.workspaces || [];
        const focusedWs = Wm.focusedWorkspace;
        const isFlagged = function(e) {
            return e.active === true || e.focused === true || e.isActive === true || e.isFocused === true;
        };
        let entry = null;
        let anyFlag = false;
        for (let i = 0; i < list.length; ++i) {
            const e = list[i];
            if (!e || e.special === true || String(e.output || "") !== String(screenName || ""))
                continue;
            if (isFlagged(e))
                anyFlag = true;
            if (String(e.name) === wsVal || String(e.id) === wsVal)
                entry = e;
        }
        if (!entry)
            return false;
        if (anyFlag)
            return !isFlagged(entry);
        if (focusedWs && Wm.focusedOutput === screenName)
            return !(focusedWs === entry || String(focusedWs.id) === String(entry.id));
        return false;
    }

    function activeWindowIsFullscreen(screenName) {
        // Re-evaluate whenever any of the window/workspace state moves.
        void root.fullscreenRecheck;
        void Wm.workspaces;
        void Wm.windows;
        void Wm.focusedWorkspace;
        void Wm.focusedOutput;

        const win = Wm.focusedWindow;
        // An empty workspace has no focused toplevel. On niri the workspace
        // fullscreen flag can trail the workspace switch for a frame (or longer),
        // which used to leave Karuma unmapped after leaving a fullscreen app.
        // No focused window means there is nothing fullscreen to hide behind.
        if (!win)
            return false;
        // A stale focused window from another workspace is not "in front" either.
        if (root.windowOnInactiveWorkspace(win, screenName))
            return false;

        const output = String(win.output || Wm.focusedOutput || "");
        if (output !== String(screenName || ""))
            return false;

        const toplevel = win.toplevel;
        if (toplevel && toplevel.fullscreen === true)
            return true;
        if (!toplevel && Wm.outputHasFullscreen(screenName))
            return true;

        let screen = null;
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; ++i) {
            if (screens[i] && screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }
        if (!screen)
            return false;

        const sw = Number(screen.width) || 0;
        const sh = Number(screen.height) || 0;
        const ww = Number(win.width) || 0;
        const wh = Number(win.height) || 0;
        if (sw <= 0 || sh <= 0 || ww <= 0 || wh <= 0)
            return false;

        const widthTolerance = Math.max(4, sw * 0.02);
        const heightTolerance = Math.max(4, sh * 0.02);
        return Math.abs(ww - sw) <= widthTolerance
            && Math.abs(wh - sh) <= heightTolerance;
    }

    // ------------------------------------------------------------ timers + probes
    Component.onCompleted: {
        if (root.isPrimary) {
            netProbe.running = true;
            btProbe.running = true;
            recProbe.running = true;
            wifiProbe.running = true;
        }
    }

    // True while every output has a fullscreen focused window and no sheet is
    // open: nothing is on screen, so the clock (and everything bound to it)
    // has no reason to tick.
    readonly property bool allBarsHidden: {
        if (root.sheet.length > 0)
            return false;
        const screens = root.barScreens;
        if (screens.length === 0)
            return false;
        for (let i = 0; i < screens.length; ++i) {
            if (!screens[i] || !root.activeWindowIsFullscreen(screens[i].name))
                return false;
        }
        return true;
    }
    onAllBarsHiddenChanged: {
        if (allBarsHidden)
            return;
        // Catch up immediately on reveal instead of waiting for the next tick.
        root.now = new Date();
        if (root.isPrimary) {
            if (!netProbe.running) netProbe.running = true;
            if (!btProbe.running) btProbe.running = true;
            if (!recProbe.running) recProbe.running = true;
            root.mediaPulse++;
        }
    }

    Timer {
        interval: 1000
        running: !root.allBarsHidden
        repeat: true
        onTriggered: root.now = new Date()
    }

    Timer {
        interval: 2500
        running: root.isPrimary && !root.allBarsHidden
        repeat: true
        onTriggered: root.mediaPulse++
    }

    // MPRIS positions are not pushed; ask for a fresh one each second so the
    // underline creeps along as the song plays.
    Timer {
        interval: 1000
        running: root.isPrimary && !root.allBarsHidden && !!root.activePlayer && root.activePlayer.isPlaying
        repeat: true
        onTriggered: { if (root.activePlayer) root.activePlayer.positionChanged(); }
    }

    Timer {
        interval: 15000
        running: root.isPrimary && !root.allBarsHidden
        repeat: true
        onTriggered: {
            if (!netProbe.running) netProbe.running = true;
            if (!btProbe.running) btProbe.running = true;
        }
    }

    Timer {
        interval: 2000
        running: root.isPrimary && !root.allBarsHidden
        repeat: true
        onTriggered: { if (!recProbe.running) recProbe.running = true; }
    }

    Timer { id: btRefresh; interval: 700; onTriggered: { if (!btProbe.running) btProbe.running = true; } }
    Timer { id: wifiRefresh; interval: 900; onTriggered: root.refreshQuick() }
    Timer {
        id: brightTimer
        interval: 60
        onTriggered: {
            const pct = root.pendingBrightness;
            root.pendingBrightness = -1;
            if (pct >= 0) Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
        }
    }
    // While the quick settings menu is open its readings are kept fresh.
    Timer {
        interval: 4000
        running: root.isPrimary && root.sheet === "quick"
        repeat: true
        onTriggered: root.refreshQuick()
    }

    // enabled / disabled; silent when nmcli is not there (the Wi-Fi tile then stays out).
    Process {
        id: wifiProbe
        command: ["sh", "-c", "nmcli radio wifi 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                root.wifiRadio = t === "enabled" ? true : (t === "disabled" ? false : null);
            }
        }
    }
    Timer { id: recRefresh; interval: 900; onTriggered: { if (!recProbe.running) recProbe.running = true; } }

    // One line: kind <TAB> name <TAB> signal. Wi-Fi first, then wired.
    Process {
        id: netProbe
        command: ["sh", "-c",
            "nmcli -t -e no -f ACTIVE,SIGNAL,SSID dev wifi list --rescan no 2>/dev/null | "
            + "awk -F: '$1==\"yes\"{s=$0; sub(/^yes:[0-9]+:/,\"\",s); printf \"wifi\\t%s\\t%s\\n\", s, $2; f=1; exit} END{exit f?0:1}' "
            + "|| { nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -q '^ethernet:connected' && printf 'ethernet\\tWired\\t100\\n'; }"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.replace(/\n+$/, "").split("\t");
                if (f[0] === "wifi") {
                    const sig = Number(f[2]);
                    root.netInfo = { kind: "wifi", name: f[1] || "Wi-Fi", bars: HD.bars(sig), off: false, needsYou: false };
                } else if (f[0] === "ethernet") {
                    root.netInfo = { kind: "ethernet", name: "Wired", bars: 4, off: false, needsYou: false };
                } else {
                    root.netInfo = { kind: "disconnected", name: "Offline", bars: 0, off: true, needsYou: true };
                }
            }
        }
    }

    // One line: powered <TAB> name of the first connected device. Silent when
    // there is no adapter (the 双 reading then hides).
    Process {
        id: btProbe
        command: ["sh", "-c",
            "p=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2; exit}'); [ -n \"$p\" ] || exit 0; "
            + "n=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-); "
            + "if [ -z \"$n\" ] && [ \"$p\" = yes ]; then "
            + "n=$(bluetoothctl devices 2>/dev/null | while read -r _ mac name; do "
            + "if bluetoothctl info \"$mac\" 2>/dev/null | grep -q 'Connected: yes'; then echo \"$name\"; break; fi; done); fi; "
            + "printf '%s\\t%s\\n' \"$p\" \"$n\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.replace(/\n+$/, "");
                if (!t.length) {
                    root.btInfo = null;
                    return;
                }
                const f = t.split("\t");
                const on = f[0].trim().toLowerCase() === "yes";
                const dev = (f[1] || "").trim();
                root.btInfo = { enabled: on, name: !on ? "Off" : (dev.length ? dev : "On"), connected: dev.length ? 1 : 0 };
            }
        }
    }

    Process {
        id: recProbe
        command: ["sh", "-c", "pgrep -x gpu-screen-recorder >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: root.recording = this.text.trim() === "1"
        }
    }

    // Internal laptop backlight, one shared loop; silent on desktops.
    Process {
        running: root.isPrimary
        command: ["sh", "-c", "dev=$(ls /sys/class/backlight 2>/dev/null | head -n1); [ -n \"$dev\" ] || exit 0; max=$(cat /sys/class/backlight/$dev/max_brightness); last=\"\"; while true; do val=$(cat /sys/class/backlight/$dev/brightness); if [ \"$val\" != \"$last\" ]; then echo \"$(( val * 100 / max ))\"; last=\"$val\"; fi; sleep 1; done"]
        stdout: SplitParser {
            onRead: (line) => {
                const pct = parseInt(line.trim(), 10);
                if (isNaN(pct)) return;
                root.backlightPresent = true;
                root.backlightPct = Math.max(0, Math.min(100, pct));
            }
        }
    }

    // Stay-awake (目): an idle inhibitor plus a systemd one, owned once.
    Loader {
        active: root.isPrimary && root.keepAwake
        sourceComponent: Component {
            Item {
                PanelWindow {
                    id: inhibitWin
                    visible: true
                    implicitWidth: 1
                    implicitHeight: 1
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.layer: WlrLayer.Background
                    WlrLayershell.namespace: "karuma-inhibit"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    anchors { top: true; left: true }
                    IdleInhibitor { window: inhibitWin; enabled: true }
                }
                Process {
                    running: true
                    command: ["systemd-inhibit", "--what=idle:sleep", "--who=Karuma",
                              "--why=stay awake", "--mode=block", "sleep", "infinity"]
                }
            }
        }
    }

    KarumaPlugins { id: karumaPlugins }
    KarumaPalette { id: hp }

    Loader {
        active: root.isPrimary && root.hubOpen
        sourceComponent: Component {
            KarumaHub {
                pal: hp
                media: root.mediaInfo
                pluginHost: karumaPlugins
                onCloseRequested: root.hubOpen = false
            }
        }
    }

    Loader {
        active: root.isPrimary
        sourceComponent: Component {
            Item {
                id: host

                // Reserve band, once per monitor. Deliberately NOT tied to
                // fullscreen state: it is a transparent, input-less strip, so
                // keeping it mapped costs next to nothing, and a constant
                // exclusive zone means tiled windows never get resized when a
                // game/video enters or leaves fullscreen. Only the visible bar
                // window below is unmapped while hidden (same split as Ricelin).
                Variants {
                    model: root.barScreens

                    PanelWindow {
                        id: reserve
                        required property var modelData

                        readonly property real uiScale: modelData ? Math.max(0.82, Math.min(1.25, modelData.height / 1080)) : 1
                        readonly property bool vertical: hp.vertical
                        readonly property real stripHeight: Math.round(hp.barHeight * uiScale * hp.sizeScale)
                        readonly property real railWidth: Math.round(hp.railWidth * uiScale * hp.sizeScale)
                        readonly property real bandDepth: vertical
                            ? Math.round(hp.gapLeft * uiScale) + railWidth + Math.round(hp.gapRight * uiScale)
                            : Math.round(hp.gapTop * uiScale) + stripHeight + Math.round(hp.gapBottom * uiScale)

                        screen: modelData
                        visible: true
                        color: "transparent"
                        anchors {
                            top: vertical || hp.edge === "top"
                            bottom: vertical || hp.edge === "bottom"
                            left: !vertical || hp.edge === "left"
                            right: !vertical || hp.edge === "right"
                        }
                        implicitHeight: vertical ? 0 : bandDepth
                        implicitWidth: vertical ? bandDepth : 0
                        exclusionMode: hp.reserveSpace ? ExclusionMode.Normal : ExclusionMode.Ignore
                        exclusiveZone: hp.reserveSpace ? bandDepth : 0
                        aboveWindows: true
                        WlrLayershell.layer: WlrLayer.Top
                        WlrLayershell.namespace: "karuma-reserve"
                        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                        mask: emptyReserve
                        Region { id: emptyReserve; width: 0; height: 0 }
                    }
                }

                Variants {
                    model: root.barScreens

                    PanelWindow {
                        id: panel
                        required property var modelData

                        readonly property real uiScale: modelData ? Math.max(0.82, Math.min(1.25, modelData.height / 1080)) : 1
                        readonly property real k: uiScale * hp.sizeScale
                        readonly property bool vertical: hp.vertical
                        readonly property real stripHeight: Math.round(hp.barHeight * k)
                        readonly property real railWidth: Math.round(hp.railWidth * k)
                        readonly property real gapTop: Math.round(hp.gapTop * uiScale)
                        readonly property real gapBottom: Math.round(hp.gapBottom * uiScale)
                        readonly property real gapLeft: Math.round(hp.gapLeft * uiScale)
                        readonly property real gapRight: Math.round(hp.gapRight * uiScale)
                        readonly property real horizontalAvail: Math.max(1, width - gapLeft - gapRight)
                        readonly property real verticalAvail: Math.max(1, height - gapTop - gapBottom)
                        readonly property real surfaceWidth: vertical ? railWidth : Math.round(horizontalAvail * hp.lengthPercent / 100)
                        readonly property real surfaceHeight: vertical ? Math.round(verticalAvail * hp.lengthPercent / 100) : stripHeight
                        readonly property real stripX: vertical
                            ? (hp.edge === "left" ? gapLeft : width - gapRight - surfaceWidth)
                            : (hp.align === "start" ? gapLeft
                                : hp.align === "end" ? width - gapRight - surfaceWidth
                                : gapLeft + (horizontalAvail - surfaceWidth) / 2)
                        readonly property real stripY: vertical
                            ? (hp.align === "start" ? gapTop
                                : hp.align === "end" ? height - gapBottom - surfaceHeight
                                : gapTop + (verticalAvail - surfaceHeight) / 2)
                            : (hp.edge === "bottom" ? height - gapBottom - surfaceHeight : gapTop)
                        readonly property real stripBottom: stripY + surfaceHeight
                        readonly property real stripRight: stripX + surfaceWidth
                        readonly property var sheetMeta: ({
                            menu: { glyph: "印", title: "Karuma", sub: "SHELL MENU", h: 214 },
                            sound: { glyph: "音", title: "Sound", sub: "OUTPUT", h: 270 },
                            network: { glyph: "網", title: "Network", sub: "CONNECTION", h: 240 },
                            power: { glyph: "電", title: "Power", sub: "BATTERY", h: 268 },
                            media: { glyph: "楽", title: "Media", sub: "PLAYBACK", h: 270 },
                            time: { glyph: "暦", title: "Calendar", sub: "DATE AND TIME", h: 336 },
                            notices: { glyph: "報", title: "Notifications", sub: "INBOX", h: 330 },
                            overview: { glyph: "間", title: "Spaces", sub: "WORKSPACES", h: 270 }
                        })
                        readonly property var pluginEntry: root.pluginEntry(root.pluginPanelId)
                        readonly property var pluginManifest: pluginEntry ? pluginEntry.manifest : null
                        readonly property var meta: sheetKey === "plugin" ? ({
                            glyph: "拡",
                            title: pluginManifest && pluginManifest.name ? String(pluginManifest.name) : root.pluginPanelId,
                            sub: "RYOKU PLUGIN",
                            h: 360
                        }) : (sheetMeta[sheetKey] || sheetMeta.menu)
                        readonly property real sheetHeight: meta.h * uiScale
                        readonly property bool sheetOpen: root.sheet.length > 0 && root.sheetScreen === modelData.name

                        // The sheet fades and slides in and out. It keeps the page it was showing
                        // (root.sheet is empty by the time it fades) and stays mapped until the
                        // exit has played; with animations off sheetT jumps and nothing lingers.
                        property string sheetKey: ""
                        readonly property bool quickKey: sheetKey === "quick"
                        property real sheetT: sheetOpen ? 1 : 0
                        Behavior on sheetT {
                            enabled: hp.animate
                            NumberAnimation {
                                duration: panel.sheetOpen ? 210 : 140
                                easing.type: panel.sheetOpen ? Easing.OutCubic : Easing.InCubic
                            }
                        }
                        readonly property bool sheetVisible: sheetOpen || sheetT > 0.001
                        // The quick settings menu is as tall as its controls; the other sheets are one size.
                        readonly property real sheetExtent: quickKey ? quickPanel.height : sheetHeight
                        Connections {
                            target: root
                            function onSheetChanged() { if (root.sheet.length > 0) panel.sheetKey = root.sheet; }
                        }
                        readonly property bool fullscreen: modelData ? root.activeWindowIsFullscreen(modelData.name) : false
                        readonly property var workspaceRows: root.workspaceRowsFor(modelData ? modelData.name : "")
                        readonly property string activeWorkspace: root.activeWorkspaceFor(modelData ? modelData.name : "")

                        readonly property bool barHidden: hp.fullscreenMode === "hide" && fullscreen && !sheetOpen

                        // opacity 0 + an empty input mask still left this layer
                        // surface mapped, painted and composited every frame
                        // while a game was fullscreen. Unmap it instead. The
                        // unmap is delayed by the fade-out so the opacity
                        // Behavior still plays, and the reveal is instant so
                        // the fade-in is never clipped. The reserve window
                        // above keeps the exclusive zone, so nothing reflows.
                        visible: !barHidden || hideDelay.running
                        Timer {
                            id: hideDelay
                            interval: 160
                        }
                        onBarHiddenChanged: barHidden ? hideDelay.restart() : hideDelay.stop()
                        // While hidden, keep re-asking whether fullscreen is still
                        // true; recovers if the compositor's state update is missed.
                        Timer {
                            interval: 400
                            repeat: true
                            running: panel.barHidden
                            onTriggered: root.fullscreenRecheck++
                        }

                        screen: modelData
                        color: "transparent"
                        anchors {
                            top: vertical || hp.edge === "top"
                            bottom: vertical || hp.edge === "bottom"
                            left: !vertical || hp.edge === "left"
                            right: !vertical || hp.edge === "right"
                        }
                        implicitHeight: vertical ? 0
                            : gapTop + stripHeight + gapBottom + (sheetVisible ? sheetExtent + 26 * uiScale : 0)
                        implicitWidth: vertical
                            ? gapLeft + railWidth + gapRight + (sheetVisible ? 506 * uiScale : 0) : 0
                        exclusionMode: ExclusionMode.Ignore
                        aboveWindows: true
                        WlrLayershell.layer: WlrLayer.Top
                        WlrLayershell.namespace: "karuma-bar"
                        WlrLayershell.keyboardFocus: sheetOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                        mask: sheetOpen ? wholeRegion
                            : (panel.barHidden ? hiddenRegion : (hp.islands ? islandsRegion : stripRegion))
                        Region { id: stripRegion; x: panel.stripX; y: panel.stripY; width: panel.surfaceWidth; height: panel.surfaceHeight }
                        Region {
                            id: islandsRegion
                            Region { item: surface.item ? surface.item.leftIslandRegion : null }
                            Region { item: surface.item ? surface.item.centerIslandRegion : null }
                            Region { item: surface.item ? surface.item.rightIslandRegion : null }
                        }
                        Region { id: hiddenRegion; width: 0; height: 0 }
                        Region { id: wholeRegion; width: panel.width; height: panel.height }

                        FocusScope {
                            id: inputScope
                            anchors.fill: parent
                            focus: panel.sheetOpen
                            Keys.onEscapePressed: root.closeSheet()
                            Keys.onBackPressed: root.closeSheet()
                        }

                        onSheetOpenChanged: if (sheetOpen) inputScope.forceActiveFocus()
                        onFullscreenChanged: if (hp.fullscreenMode === "hide" && fullscreen && root.sheetScreen === modelData.name) root.closeSheet()

                        MouseArea {
                            anchors.fill: parent
                            z: 0
                            enabled: panel.sheetOpen
                            acceptedButtons: Qt.LeftButton
                            onClicked: (mouse) => {
                                const shown = panel.quickKey ? quickPanel : sheet;
                                const insideSheet = mouse.x >= shown.x && mouse.x <= shown.x + shown.width
                                    && mouse.y >= shown.y && mouse.y <= shown.y + shown.height;
                                if (!insideSheet)
                                    root.closeSheet();
                            }
                        }

                        Loader {
                            id: surface
                            z: 1
                            x: panel.stripX
                            y: panel.stripY
                            width: panel.surfaceWidth
                            height: panel.surfaceHeight
                            opacity: panel.barHidden ? 0 : 1
                            sourceComponent: panel.vertical ? railSurface : horizontalSurface
                            Behavior on opacity { enabled: hp.animate; NumberAnimation { duration: 130 } }
                        }

                        Component {
                            id: horizontalSurface
                            BarSurface {
                                width: surface.width; height: surface.height
                                pal: hp; k: panel.k
                                now: root.now; spaces: panel.workspaceRows; activeWorkspace: panel.activeWorkspace
                                appClass: root.focusedClass; windowTitle: root.focusedRawTitle; home: Quickshell.env("HOME") || ""
                                media: root.mediaInfo; volume: root.volumeInfo; network: root.netInfo; bluetooth: root.btInfo
                                battery: root.batteryInfo; brightness: root.brightnessInfo; notifications: root.notifList
                                indicators: root.indicatorList; quickOpen: panel.sheetOpen && panel.quickKey
                                pluginHost: karumaPlugins; screenName: panel.modelData ? panel.modelData.name : ""
                                activePluginPanelId: root.sheet === "plugin" && root.sheetScreen === screenName ? root.pluginPanelId : ""
                                onSealClicked: button => root.toggleHub()
                                onClearNotifications: root.clearNotifications()
                                onWorkspaceActivated: id => Wm.focusWorkspace(String(id))
                                onWorkspaceStepped: delta => root.stepWorkspace(panel.modelData.name, delta)
                                onMediaAction: name => root.mediaAction(name)
                                onClockClicked: root.toggleSheet("time", panel.modelData.name)
                                onQuickClicked: root.toggleSheet("quick", panel.modelData.name)
                                onStatusAction: (name, how) => root.statusAction(name, how, panel.modelData.name)
                                onInboxAction: how => { if (how === "click") root.toggleSheet("notices", panel.modelData.name) }
                                onIndicatorAction: (key, how) => {
                                    if (key === "record") root.toggleRecording()
                                    else if (key === "awake") root.keepAwake = !root.keepAwake
                                }
                                onPluginPanelRequested: (id, api) => root.openPluginPanel(id, api, panel.modelData.name)
                            }
                        }

                        Component {
                            id: railSurface
                            RailSurface {
                                width: surface.width; height: surface.height
                                pal: hp; k: panel.k
                                now: root.now; spaces: panel.workspaceRows; activeWorkspace: panel.activeWorkspace
                                appClass: root.focusedClass; windowTitle: root.focusedRawTitle; home: Quickshell.env("HOME") || ""
                                media: root.mediaInfo; volume: root.volumeInfo; network: root.netInfo; bluetooth: root.btInfo
                                battery: root.batteryInfo; brightness: root.brightnessInfo; notifications: root.notifList
                                indicators: root.indicatorList; quickOpen: panel.sheetOpen && panel.quickKey
                                pluginHost: karumaPlugins; screenName: panel.modelData ? panel.modelData.name : ""
                                activePluginPanelId: root.sheet === "plugin" && root.sheetScreen === screenName ? root.pluginPanelId : ""
                                onSealClicked: button => root.toggleHub()
                                onClearNotifications: root.clearNotifications()
                                onWorkspaceActivated: id => Wm.focusWorkspace(String(id))
                                onWorkspaceStepped: delta => root.stepWorkspace(panel.modelData.name, delta)
                                onMediaAction: name => root.mediaAction(name)
                                onClockClicked: root.toggleSheet("time", panel.modelData.name)
                                onQuickClicked: root.toggleSheet("quick", panel.modelData.name)
                                onStatusAction: (name, how) => root.statusAction(name, how, panel.modelData.name)
                                onInboxAction: how => { if (how === "click") root.toggleSheet("notices", panel.modelData.name) }
                                onIndicatorAction: (key, how) => {
                                    if (key === "record") root.toggleRecording()
                                    else if (key === "awake") root.keepAwake = !root.keepAwake
                                }
                                onPluginPanelRequested: (id, api) => root.openPluginPanel(id, api, panel.modelData.name)
                            }
                        }

                        PopupFrame {
                            id: sheet
                            z: 4
                            visible: panel.sheetVisible && !panel.quickKey
                            opacity: panel.sheetT
                            pal: hp
                            k: panel.uiScale
                            padding: 18
                            x: panel.vertical
                                ? (hp.edge === "left" ? panel.stripRight + 8 * panel.uiScale
                                    : panel.stripX - width - 8 * panel.uiScale)
                                : Math.max(10 * panel.uiScale, (panel.width - width) / 2)
                            y: panel.vertical
                                ? Math.max(10 * panel.uiScale, Math.min(panel.height - height - 10 * panel.uiScale,
                                    panel.stripY + (panel.surfaceHeight - height) / 2))
                                : (hp.edge === "bottom"
                                    ? panel.stripY - height - 8 * panel.uiScale + (1 - panel.sheetT) * 10 * panel.uiScale
                                    : panel.stripBottom + 8 * panel.uiScale - (1 - panel.sheetT) * 10 * panel.uiScale)
                            width: Math.min(480 * panel.uiScale, Math.max(280 * panel.uiScale, panel.width - 20 * panel.uiScale))
                            height: panel.sheetHeight

                            Column {
                                anchors.fill: parent
                                spacing: 14 * panel.uiScale

                                PopupHeader {
                                    pal: hp
                                    k: panel.uiScale
                                    glyph: panel.meta.glyph
                                    title: panel.meta.title
                                    eyebrow: "KARUMA · " + panel.meta.sub
                                    onCloseClicked: root.closeSheet()
                                }

                                Loader {
                                    id: pageLoader
                                    active: panel.sheetVisible && !panel.quickKey
                                    width: parent.width
                                    height: parent.height - 52 * panel.uiScale
                                    sourceComponent: panel.sheetKey === "menu" ? menuPage
                                        : panel.sheetKey === "sound" ? soundPage
                                        : panel.sheetKey === "network" ? networkPage
                                        : panel.sheetKey === "power" ? powerPage
                                        : panel.sheetKey === "media" ? mediaPage
                                        : panel.sheetKey === "time" ? timePage
                                        : panel.sheetKey === "notices" ? noticesPage
                                        : panel.sheetKey === "overview" ? overviewPage
                                        : panel.sheetKey === "plugin" ? pluginPage : menuPage
                                    // Moving from one page to another (the sheet itself is already open)
                                    // crossfades; the first page rides in with the sheet.
                                    onLoaded: { if (panel.sheetT > 0.99 && hp.animate) pageFade.restart(); }
                                    NumberAnimation { id: pageFade; target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutQuad }
                                }
                            }
                        }

                        // The quick settings menu: its own small panel under the 設 button's
                        // side of the strip, sized to the controls it shows.
                        PopupFrame {
                            id: quickPanel
                            z: 4
                            visible: panel.sheetVisible && panel.quickKey
                            opacity: panel.sheetT
                            pal: hp
                            k: panel.uiScale
                            padding: 16
                            width: Math.min(348 * panel.uiScale, Math.max(260 * panel.uiScale, panel.width - 20 * panel.uiScale))
                            height: (quickLoader.item ? quickLoader.item.implicitHeight : 0) + 2 * inner
                            x: panel.vertical
                                ? (hp.edge === "left" ? panel.stripRight + 8 * panel.uiScale
                                    : panel.stripX - width - 8 * panel.uiScale)
                                : ((surface.item && surface.item.quickOnRight)
                                    ? panel.stripRight - width - 6 * panel.uiScale
                                    : panel.stripX + 6 * panel.uiScale)
                            y: panel.vertical
                                ? Math.max(10 * panel.uiScale, Math.min(panel.height - height - 10 * panel.uiScale,
                                    panel.stripY + (panel.surfaceHeight - height) / 2))
                                : (hp.edge === "bottom"
                                    ? panel.stripY - height - 8 * panel.uiScale + (1 - panel.sheetT) * 10 * panel.uiScale
                                    : panel.stripBottom + 8 * panel.uiScale - (1 - panel.sheetT) * 10 * panel.uiScale)

                            Loader {
                                id: quickLoader
                                active: panel.sheetVisible && panel.quickKey
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                height: item ? item.implicitHeight : 0
                                sourceComponent: Component {
                                    QuickSettings {
                                        pal: hp
                                        k: panel.uiScale
                                        hiddenKey: hp.quickHiddenKey
                                        volume: root.volumeInfo
                                        brightness: root.brightnessInfo
                                        wifi: root.wifiInfo
                                        bluetooth: root.bluetoothInfo
                                        mic: root.micInfo
                                        keepAwake: root.keepAwake
                                        onVolumeSet: (level) => root.setVolume(level)
                                        onVolumeMute: root.toggleMute()
                                        onBrightnessSet: (percent) => root.setBrightness(percent)
                                        onWifiToggle: root.toggleWifi()
                                        onBluetoothToggle: root.toggleBluetooth()
                                        onMicToggle: root.toggleMic()
                                        onAwakeToggle: root.keepAwake = !root.keepAwake
                                    }
                                }
                            }
                        }

                        Component {
                            id: pluginPage
                            Item {
                                anchors.fill: parent
                                readonly property var entry: panel.pluginEntry
                                readonly property var manifest: panel.pluginManifest
                                readonly property string versionQuery: entry && entry.version
                                    ? "?v=" + encodeURIComponent(entry.version) : ""

                                Text {
                                    anchors.centerIn: parent
                                    visible: !pluginContent.item
                                    text: "PLUGIN VIEW UNAVAILABLE"
                                    color: hp.inkFaint
                                    font.family: hp.mono
                                    font.pixelSize: 10 * panel.uiScale
                                    font.letterSpacing: 1.2
                                }

                                PluginObjectSlot {
                                    id: pluginContent
                                    fill: true
                                    anchors.fill: parent
                                    source: entry && manifest && manifest.entryPoints && manifest.entryPoints.panel
                                        ? "file://" + entry.dir + "/" + manifest.entryPoints.panel + versionQuery : ""
                                    configure: (content) => {
                                        content.pluginApi = Qt.binding(() => root.pluginPanelApi)
                                        if ("density" in content) content.density = "full"
                                        if ("s" in content) content.s = panel.uiScale
                                        if ("widthBudget" in content) content.widthBudget = Math.max(240, width)
                                        if ("active" in content) content.active = true
                                    }
                                }
                            }
                        }

                        Component {
                            id: menuPage
                            Grid {
                                columns: 3
                                spacing: 8 * panel.uiScale
                                property var entries: [
                                    { key: "sound", glyph: "音", label: "SOUND", detail: "Volume, mute" },
                                    { key: "network", glyph: "網", label: "NETWORK", detail: "Connection" },
                                    { key: "power", glyph: "電", label: "POWER", detail: "Battery" },
                                    { key: "media", glyph: "楽", label: "MEDIA", detail: "Playback" },
                                    { key: "time", glyph: "暦", label: "CALENDAR", detail: "Date and time" },
                                    { key: "overview", glyph: "間", label: "SPACES", detail: "Workspaces" }
                                ]
                                Repeater {
                                    model: parent.entries
                                    delegate: PaperButton {
                                        required property var modelData
                                        pal: hp
                                        uiScale: panel.uiScale
                                        width: Math.floor((pageLoader.width - 16 * panel.uiScale) / 3)
                                        glyph: modelData.glyph
                                        label: modelData.label
                                        detail: modelData.detail
                                        onActivated: root.openSheet(modelData.key, panel.modelData.name)
                                    }
                                }
                            }
                        }

                        Component {
                            id: soundPage
                            Column {
                                width: pageLoader.width
                                spacing: 14 * panel.uiScale
                                Row {
                                    width: parent.width
                                    Column {
                                        width: parent.width - muteBtn.width
                                        spacing: 2 * panel.uiScale
                                        Eyebrow { width: parent.width; pal: hp; k: panel.uiScale; text: root.muted ? "OUTPUT · MUTED" : "OUTPUT · DEFAULT DEVICE" }
                                        Text {
                                            text: root.muted ? "Muted" : Math.round(root.volume * 100) + "%"
                                            color: root.muted ? hp.urgent : hp.ink
                                            font.family: hp.display
                                            font.pixelSize: 38 * panel.uiScale
                                        }
                                    }
                                    ActionButton {
                                        id: muteBtn
                                        anchors.verticalCenter: parent.verticalCenter
                                        pal: hp
                                        k: panel.uiScale
                                        primary: root.muted
                                        glyph: root.muted ? "×" : "耳"
                                        text: root.muted ? "UNMUTE" : "MUTE"
                                        onActivated: root.toggleMute()
                                    }
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 56 * panel.uiScale
                                    radius: hp.radiusM * panel.uiScale
                                    color: hp.raised
                                    border.width: 1
                                    border.color: hp.lineSoft
                                    LevelRow {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 * panel.uiScale }
                                        pal: hp
                                        k: panel.uiScale
                                        glyph: root.muted ? "×" : "耳"
                                        glyphIsButton: true
                                        level: root.volume
                                        urgent: root.muted
                                        readout: root.muted ? "MUTE" : Math.round(root.volume * 100) + "%"
                                        onMoved: (v) => root.setVolume(v)
                                        onGlyphClicked: root.toggleMute()
                                    }
                                }
                            }
                        }

                        Component {
                            id: networkPage
                            Column {
                                width: pageLoader.width
                                spacing: 14 * panel.uiScale
                                Rectangle {
                                    width: parent.width
                                    height: 84 * panel.uiScale
                                    radius: hp.radiusM * panel.uiScale
                                    color: hp.raised
                                    border.width: 1
                                    border.color: hp.lineSoft
                                    Rectangle {
                                        id: netDot
                                        anchors { left: parent.left; leftMargin: 16 * panel.uiScale; verticalCenter: parent.verticalCenter }
                                        width: 10 * panel.uiScale
                                        height: width
                                        radius: width / 2
                                        color: root.activeConnection === "Offline" ? hp.urgent : hp.seal
                                    }
                                    Column {
                                        anchors { left: netDot.right; right: parent.right; leftMargin: 14 * panel.uiScale; rightMargin: 16 * panel.uiScale; verticalCenter: parent.verticalCenter }
                                        spacing: 3 * panel.uiScale
                                        Eyebrow { width: parent.width; pal: hp; k: panel.uiScale; text: "ACTIVE CONNECTION" }
                                        Text { width: parent.width; text: root.activeConnection; color: hp.ink; font.family: hp.display; font.pixelSize: 22 * panel.uiScale; elide: Text.ElideRight }
                                        Text { width: parent.width; text: root.activeConnection === "Offline" ? "No active NetworkManager connection was reported." : "NetworkManager reports this connection as active."; color: hp.inkMuted; font.family: hp.text; font.pixelSize: 11 * panel.uiScale; elide: Text.ElideRight }
                                    }
                                }
                                ActionButton {
                                    pal: hp
                                    k: panel.uiScale
                                    glyph: "網"
                                    text: "REFRESH"
                                    onActivated: { if (!netProbe.running) netProbe.running = true; }
                                }
                            }
                        }

                        Component {
                            id: powerPage
                            Column {
                                width: pageLoader.width
                                spacing: 12 * panel.uiScale
                                Eyebrow { width: parent.width; pal: hp; k: panel.uiScale; text: root.hasBattery ? (root.charging ? "充 · CHARGING" : "電 · BATTERY") : "AC POWER" }
                                Text {
                                    text: root.hasBattery ? root.batteryPercent + "%" : "No battery"
                                    color: root.hasBattery && root.batteryPercent <= 20 && !root.charging ? hp.urgent : hp.ink
                                    font.family: hp.display
                                    font.pixelSize: 40 * panel.uiScale
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 8 * panel.uiScale
                                    radius: height / 2
                                    color: hp.hover
                                    border.width: 1
                                    border.color: hp.lineSoft
                                    Rectangle {
                                        width: Math.max(parent.height, parent.width * (root.hasBattery ? root.batteryPercent / 100 : 1))
                                        height: parent.height
                                        radius: height / 2
                                        color: root.hasBattery && root.batteryPercent <= 20 && !root.charging ? hp.urgent : (root.charging ? hp.seal : hp.ink)
                                    }
                                }
                                Text { text: root.stateLabel(); color: hp.inkMuted; font.family: hp.text; font.pixelSize: 12 * panel.uiScale }
                            }
                        }

                        Component {
                            id: mediaPage
                            Column {
                                width: pageLoader.width
                                spacing: 10 * panel.uiScale
                                Eyebrow { width: parent.width; pal: hp; k: panel.uiScale; text: root.activePlayer && root.activePlayer.isPlaying ? "NOW PLAYING" : "PLAYBACK" }
                                Text { width: parent.width; text: root.mediaTitle; color: hp.ink; font.family: hp.display; font.italic: true; font.pixelSize: 22 * panel.uiScale; elide: Text.ElideRight }
                                Text { width: parent.width; text: root.mediaArtist; color: hp.inkMuted; font.family: hp.text; font.pixelSize: 12 * panel.uiScale; elide: Text.ElideRight }
                                Rectangle {
                                    visible: root.mediaInfo !== null && root.mediaInfo.hasLength
                                    width: parent.width
                                    height: 4 * panel.uiScale
                                    radius: height / 2
                                    color: hp.hover
                                    Rectangle {
                                        width: parent.width * (root.mediaInfo ? root.mediaInfo.progress : 0)
                                        height: parent.height
                                        radius: height / 2
                                        color: hp.seal
                                        opacity: root.mediaInfo && root.mediaInfo.playing ? 1 : 0.5
                                    }
                                }
                                Item {
                                    width: parent.width
                                    height: 36 * panel.uiScale
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 10 * panel.uiScale
                                        ActionButton { pal: hp; k: panel.uiScale; glyph: "◀"; text: "PREV"; disabled: !root.activePlayer || !root.activePlayer.canGoPrevious; onActivated: root.mediaAction("previous") }
                                        ActionButton { pal: hp; k: panel.uiScale; primary: true; glyph: root.activePlayer && root.activePlayer.isPlaying ? "Ⅱ" : "▶"; text: root.activePlayer && root.activePlayer.isPlaying ? "PAUSE" : "PLAY"; disabled: !root.activePlayer || !root.activePlayer.canTogglePlaying; onActivated: root.mediaAction("playPause") }
                                        ActionButton { pal: hp; k: panel.uiScale; glyph: "▶"; text: "NEXT"; disabled: !root.activePlayer || !root.activePlayer.canGoNext; onActivated: root.mediaAction("next") }
                                    }
                                }
                            }
                        }

                        Component {
                            id: timePage
                            Item {
                                id: tp
                                width: pageLoader.width
                                height: pageLoader.height
                                // Months away from the current one; the month title jumps back.
                                property int monthOffset: 0
                                readonly property var shown: Cal.shiftMonth(root.now, monthOffset)
                                readonly property int firstDay: Qt.locale().firstDayOfWeek
                                readonly property var grid: Cal.monthGrid(shown.year, shown.month, firstDay)
                                readonly property real calW: width - 168 * panel.uiScale
                                readonly property real cellW: Math.floor(calW / 7)

                                Column {
                                    id: today
                                    width: 140 * panel.uiScale
                                    spacing: 2 * panel.uiScale
                                    Eyebrow { width: parent.width; pal: hp; k: panel.uiScale; text: Qt.formatDate(root.now, "dddd").toUpperCase() }
                                    Text { text: Qt.formatDate(root.now, "dd"); color: hp.ink; font.family: hp.display; font.pixelSize: 58 * panel.uiScale }
                                    Text { text: Qt.formatDate(root.now, "MMMM yyyy"); color: hp.ink; font.family: hp.text; font.pixelSize: 13 * panel.uiScale }
                                    Item { width: 1; height: 10 * panel.uiScale }
                                    Text { text: Qt.formatDateTime(root.now, hp.hours === "24h" ? "HH:mm:ss" : "h:mm:ss AP"); color: hp.ink; font.family: hp.mono; font.pixelSize: 17 * panel.uiScale }
                                    Eyebrow { width: parent.width; pal: hp; k: panel.uiScale; text: "LOCAL TIME" }
                                }

                                Rectangle {
                                    x: today.width + 12 * panel.uiScale
                                    width: 1
                                    height: parent.height
                                    color: hp.lineSoft
                                }

                                Column {
                                    anchors.right: parent.right
                                    width: tp.calW
                                    spacing: 6 * panel.uiScale

                                    Item {
                                        width: parent.width
                                        height: 26 * panel.uiScale
                                        Rectangle {
                                            id: prevBtn
                                            anchors.left: parent.left
                                            width: 26 * panel.uiScale; height: width
                                            radius: hp.radiusS * panel.uiScale
                                            color: prevArea.pressed ? hp.press : (prevArea.containsMouse ? hp.hover : "transparent")
                                            Text { anchors.centerIn: parent; text: "‹"; color: hp.ink; font.family: hp.mono; font.pixelSize: 16 * panel.uiScale }
                                            MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tp.monthOffset -= 1 }
                                        }
                                        Item {
                                            anchors { left: prevBtn.right; right: nextBtn.left; top: parent.top; bottom: parent.bottom }
                                            Text {
                                                anchors.centerIn: parent
                                                text: Qt.locale().monthName(tp.shown.month, Locale.LongFormat) + " " + tp.shown.year
                                                color: tp.monthOffset === 0 ? hp.ink : hp.seal
                                                font.family: hp.text
                                                font.pixelSize: 12 * panel.uiScale
                                                font.weight: Font.Medium
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: tp.monthOffset === 0 ? Qt.ArrowCursor : Qt.PointingHandCursor; onClicked: tp.monthOffset = 0 }
                                        }
                                        Rectangle {
                                            id: nextBtn
                                            anchors.right: parent.right
                                            width: 26 * panel.uiScale; height: width
                                            radius: hp.radiusS * panel.uiScale
                                            color: nextArea.pressed ? hp.press : (nextArea.containsMouse ? hp.hover : "transparent")
                                            Text { anchors.centerIn: parent; text: "›"; color: hp.ink; font.family: hp.mono; font.pixelSize: 16 * panel.uiScale }
                                            MouseArea { id: nextArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tp.monthOffset += 1 }
                                        }
                                    }

                                    Row {
                                        Repeater {
                                            model: Cal.weekdayOrder(tp.firstDay)
                                            delegate: Text {
                                                required property int modelData
                                                width: tp.cellW
                                                height: 16 * panel.uiScale
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Qt.locale().dayName(modelData, Locale.ShortFormat).slice(0, 2).toUpperCase()
                                                color: hp.inkFaint
                                                font.family: hp.mono
                                                font.pixelSize: 8.5 * panel.uiScale
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }

                                    Grid {
                                        columns: 7
                                        Repeater {
                                            model: tp.grid.cells
                                            delegate: Item {
                                                id: dayCell
                                                required property var modelData
                                                readonly property bool isToday: Cal.isToday(modelData, root.now)
                                                width: tp.cellW
                                                height: 30 * panel.uiScale
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: Math.min(parent.width, parent.height) - 3 * panel.uiScale
                                                    height: width
                                                    radius: hp.radiusS * panel.uiScale
                                                    color: dayCell.isToday ? hp.bone : (dayArea.containsMouse ? hp.hover : "transparent")
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: dayCell.modelData.day
                                                    color: dayCell.isToday ? hp.boneInk : (dayCell.modelData.inMonth ? hp.ink : hp.inkFaint)
                                                    font.family: hp.text
                                                    font.pixelSize: 12 * panel.uiScale
                                                    font.weight: dayCell.isToday ? Font.Bold : Font.Normal
                                                }
                                                MouseArea { id: dayArea; anchors.fill: parent; hoverEnabled: true }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Component {
                            id: noticesPage
                            Column {
                                width: pageLoader.width
                                spacing: 10 * panel.uiScale
                                Item {
                                    width: parent.width
                                    height: 32 * panel.uiScale
                                    Eyebrow {
                                        anchors { left: parent.left; right: clearBtn.left; verticalCenter: parent.verticalCenter }
                                        pal: hp
                                        k: panel.uiScale
                                        text: root.notifList.length > 0 ? "報 · " + root.notifList.length + " WAITING" : "報 · ALL QUIET"
                                    }
                                    ActionButton {
                                        id: clearBtn
                                        visible: root.notifList.length > 0
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        pal: hp
                                        k: panel.uiScale
                                        implicitHeight: 28 * panel.uiScale
                                        glyph: "消"
                                        text: "CLEAR ALL"
                                        onActivated: root.clearNotifications()
                                    }
                                }
                                Column {
                                    visible: root.notifList.length === 0
                                    width: parent.width
                                    topPadding: 22 * panel.uiScale
                                    spacing: 6 * panel.uiScale
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "静"; color: hp.inkFaint; font.family: hp.jp; font.pixelSize: 40 * panel.uiScale }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Nothing waiting for you"; color: hp.inkMuted; font.family: hp.text; font.pixelSize: 12 * panel.uiScale }
                                }
                                Flickable {
                                    visible: root.notifList.length > 0
                                    width: parent.width
                                    height: pageLoader.height - 42 * panel.uiScale
                                    contentWidth: width
                                    contentHeight: noteColumn.height
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    Column {
                                        id: noteColumn
                                        width: parent.width
                                        spacing: 6 * panel.uiScale
                                        Repeater {
                                            model: root.notifList.slice(0, 30)
                                            delegate: Rectangle {
                                                id: note
                                                required property var modelData
                                                width: noteColumn.width
                                                height: 48 * panel.uiScale
                                                radius: hp.radiusM * panel.uiScale
                                                color: noteArea.containsMouse ? hp.hover : hp.raised
                                                border.width: 1
                                                border.color: note.modelData.urgent ? hp.sealEdge : hp.lineSoft
                                                Rectangle {
                                                    id: noteBadge
                                                    anchors { left: parent.left; leftMargin: 10 * panel.uiScale; verticalCenter: parent.verticalCenter }
                                                    width: 30 * panel.uiScale
                                                    height: width
                                                    radius: (hp.radiusS + 2) * panel.uiScale
                                                    color: note.modelData.urgent ? hp.seal : hp.sealTint
                                                    Text { anchors.centerIn: parent; text: String(note.modelData.glyph); color: note.modelData.urgent ? hp.onSeal : hp.seal; font.family: hp.display; font.pixelSize: 14 * panel.uiScale }
                                                }
                                                Column {
                                                    anchors { left: noteBadge.right; right: parent.right; leftMargin: 12 * panel.uiScale; rightMargin: 12 * panel.uiScale; verticalCenter: parent.verticalCenter }
                                                    spacing: 2 * panel.uiScale
                                                    Eyebrow { width: parent.width; pal: hp; k: panel.uiScale; text: String(note.modelData.app).toUpperCase() }
                                                    Text { width: parent.width; text: note.modelData.summary; color: hp.ink; font.family: hp.text; font.pixelSize: 12 * panel.uiScale; elide: Text.ElideRight }
                                                }
                                                MouseArea { id: noteArea; anchors.fill: parent; hoverEnabled: true }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Component {
                            id: overviewPage
                            Column {
                                width: pageLoader.width
                                spacing: 10 * panel.uiScale
                                Eyebrow { width: parent.width; pal: hp; k: panel.uiScale; text: "WORKSPACES ON THIS OUTPUT" }
                                Flow {
                                    width: parent.width
                                    spacing: 6 * panel.uiScale
                                    Repeater {
                                        model: panel.workspaceRows
                                        delegate: SpaceTile {
                                            required property var modelData
                                            pal: hp
                                            k: panel.uiScale
                                            mark: Schema.workspaceText(hp.workspaceStyle, modelData.id, modelData.label) || modelData.label
                                            name: String(modelData.id).slice(0, 7)
                                            count: modelData.count
                                            selected: String(modelData.id) === String(panel.activeWorkspace)
                                            onActivated: { Wm.focusWorkspace(String(modelData.id)); root.closeSheet(); }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
