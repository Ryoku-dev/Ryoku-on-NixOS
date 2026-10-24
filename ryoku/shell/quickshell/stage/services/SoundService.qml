pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import stage.modules.common
import Ryoku.Ui.Singletons

Singleton {
    id: root

    readonly property bool enabled: Config.options.sounds.enable === true
    readonly property int volume: Math.max(0, Math.min(100, Number(Config.options.sounds.volume) || 0))
    readonly property real _initTime: Date.now()
    property var _lastPlayed: ({})
    readonly property var _minIntervalMs: ({
        volumeChange: 150,
        screenshot: 300,
        devices: 1000
    })
    readonly property var _startupGraceMs: ({
        battery: 5000,
        devices: 10000,
        lock: 10000
    })
    property Process _loopProc: Process { command: [] }

    function _toNames(events) {
        if (typeof events === "string")
            return [events];
        return events ? Array.from(events) : [];
    }

    function _categoryEnabled(category): bool {
        return category === "" || Config.options.sounds[category] !== false;
    }

    function _customFile(category): string {
        return String(Config.options.sounds.custom?.[category] ?? "");
    }

    function _pulseVolume(): int {
        return Math.round(root.volume / 100 * 65536);
    }

    function _candidates(category, events, themeId, useCustom) {
        const candidates = [];
        const custom = useCustom ? root._customFile(String(category)) : "";
        if (custom.length > 0)
            candidates.push(custom.replace(/^file:\/\//, ""));
        const theme = String(themeId || Config.options.sounds.theme || "freedesktop");
        for (const name of root._toNames(events)) {
            candidates.push(`/usr/share/sounds/${theme}/stereo/${name}.oga`,
                `/usr/share/sounds/${theme}/stereo/${name}.ogg`,
                `/usr/share/sounds/${theme}/stereo/${name}.wav`);
            if (theme !== "freedesktop")
                candidates.push(`/usr/share/sounds/freedesktop/stereo/${name}.oga`,
                    `/usr/share/sounds/freedesktop/stereo/${name}.ogg`,
                    `/usr/share/sounds/freedesktop/stereo/${name}.wav`);
        }
        return candidates;
    }

    function _playCandidates(candidates): void {
        const script = "volume=\"$1\"; shift; for file do [ -f \"$file\" ] || continue; exec paplay --volume \"$volume\" \"$file\"; done; exit 0";
        Spawn.run(["sh", "-c", script, "ryoku-sound", String(root._pulseVolume())].concat(candidates));
    }

    function playEvent(category, events): void {
        if (!root.enabled || !root._categoryEnabled(String(category)))
            return;
        const now = Date.now();
        if (now - root._initTime < (root._startupGraceMs[category] ?? 0))
            return;
        const interval = root._minIntervalMs[category] ?? 0;
        if (interval > 0 && now - (root._lastPlayed[category] ?? 0) < interval)
            return;
        root._lastPlayed[category] = now;
        root._playCandidates(root._candidates(category, events, "", true));
    }

    // A notification chime is the Hub's notification cue, so the master switch,
    // the cue's own switch, the volume and the user's file in General > Sounds
    // apply to it. The daemon plays it once this service's own switches pass.
    function playNotificationCue(critical: bool): void {
        if (!root.enabled || !root._categoryEnabled("notifications"))
            return;
        Quickshell.execDetached(["ryoku-shell", "sound", critical ? "notification-critical" : "notification"]);
    }

    function preview(themeId, events): void {
        root._playCandidates(root._candidates("", events, themeId, false));
    }

    function previewFile(path): void {
        root._playCandidates([String(path ?? "").replace(/^file:\/\//, "")]);
    }

    // Alarm loops deliberately bypass the master UI-sound switch. The caller
    // owns the alarm category toggle; turning off interface blips must not
    // silence an armed alarm.
    function startLoop(category, events, fadeSeconds): void {
        root.stopLoop();
        const candidates = root._candidates(category, events, "", true);
        const script = "volume=\"$1\"; shift; for file do [ -f \"$file\" ] || continue; trap '[ -n \"$child\" ] && kill \"$child\" 2>/dev/null; exit 0' TERM INT; while :; do paplay --volume \"$volume\" \"$file\" & child=$!; wait \"$child\" || exit 0; child=; done; done; exit 0";
        root._loopProc.command = ["sh", "-c", script, "ryoku-sound-loop", String(root._pulseVolume())].concat(candidates);
        root._loopProc.running = true;
    }

    function stopLoop(): void {
        if (!root._loopProc.running)
            return;
        root._loopProc.signal("SIGTERM");
        root._loopProc.running = false;
    }
}
