pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import ".."
import Quickshell
import Quickshell.Io
import stage.modules.common as StageDirs

/**
 * The ii dock's sound events.
 *
 * The reference looped or fired freedesktop theme sounds; Ryoku has no
 * always-on sound daemon, so this plays the same events with paplay through
 * a shell that picks the first candidate that exists. A loop (the alarm
 * ring) is one tracked paplay process: startLoop replaces any running one,
 * stopLoop signals it. Silence is always safe: a missing theme, file or
 * paplay is a no-op, never a failure.
 */
Singleton {
    id: root

    readonly property bool enabled: StageDirs.Config.options.sounds.enable === true
    readonly property int volume: Math.max(0, Math.min(100, Number(StageDirs.Config.options.sounds.volume) || 0))

    property Process _loopProc: Process { command: [] }

    function themeName(): string {
        return String(StageDirs.Config.options.sounds.theme || "freedesktop");
    }

    function customFile(event): string {
        return String(StageDirs.Config.options.sounds.custom?.[event] || "");
    }

    function playEvent(event, name) {
        if (!root.enabled)
            return;
        const vol = Math.round(root.volume * 0.6);
        const custom = root.customFile(String(event));
        const theme = root.themeName();
        const candidates = [];
        if (custom.length > 0)
            candidates.push(custom);
        candidates.push(`/usr/share/sounds/${theme}/stereo/${name}.ogg`,
            `/usr/share/sounds/${theme}/stereo/${name}.wav`,
            `/usr/share/sounds/freedesktop/stereo/${name}.ogg`);
        const script = candidates.map(f => `test -e '${f}' && exec paplay --volume ${vol} '${f}'`).join(" || ");
        Quickshell.execDetached(["sh", "-c", `${script} || true`]);
    }

    function playEventFile(value: string) {
        if (!root.enabled)
            return;
        Quickshell.execDetached(["sh", "-c", `test -e '${value}' && exec paplay --volume ${Math.round(root.volume * 0.6)} '${value}' || true`]);
    }

    function preview(theme, name) {
        root.playEvent("alarm", name);
    }

    function previewFile(value: string) {
        root.playEventFile(value);
    }

    // The alarm ring: loop the file until stopLoop. `fadeSeconds` is
    // accepted and ignored; paplay has no fade-in.
    function startLoop(event, name, fadeSeconds) {
        root.stopLoop();
        if (!root.enabled)
            return;
        const vol = Math.round(root.volume * 0.6);
        const custom = root.customFile(String(event));
        const theme = root.themeName();
        const candidates = [];
        if (custom.length > 0)
            candidates.push(custom);
        candidates.push(`/usr/share/sounds/${theme}/stereo/${name}.ogg`,
            `/usr/share/sounds/${theme}/stereo/${name}.wav`,
            `/usr/share/sounds/freedesktop/stereo/${name}.ogg`);
        const script = candidates.map(f => `test -e '${f}' && exec paplay --loop --volume ${vol} '${f}'`).join(" || ");
        root._loopProc.command = ["sh", "-c", `${script} || true`];
        root._loopProc.running = true;
    }

    function stopLoop() {
        if (root._loopProc.running)
            root._loopProc.signal("SIGTERM");
    }
}
