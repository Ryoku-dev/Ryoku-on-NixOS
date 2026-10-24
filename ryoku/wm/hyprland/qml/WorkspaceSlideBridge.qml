pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Provider bridge for the workspace-slide reading. The neutral loader binds
// nothing and only reads the parsed fields plus the refreshed() signal, so the
// compositor's own animation table is what travels out, never a guess.
//
// `hyprctl animations -j` answers with the configured animation leaves and the
// bezier table. The overlay has to move its ink exactly as the compositor moves
// the windows, so it reads the real numbers here rather than hard-coding a
// duration and a curve copied out of a config by hand.
Item {
    id: root

    /// False when the compositor animates workspaces instantly: nothing to travel with.
    property bool slides: true
    /// "x", "y" or "none": which way the sheets go, from the animation's style.
    property string axis: "x"
    /// The `slidefade N%` distance as a fraction of the screen; 1 for a plain slide.
    property real distance: 1
    /// Whether the sheets crossfade as they go (`fade`, `slidefade`, `slidefadevert`).
    property bool fade: false
    /// The animation's duration in milliseconds.
    property int durationMs: 500
    /// Six values: the two bezier control points and the end point, which
    /// Easing.BezierSpline requires to be exactly (1, 1).
    property var curve: [0.25, 0.1, 0.25, 1, 1, 1]

    /// Emitted after every read, so the loader can re-publish and a consumer
    /// that only wants the value once can stop listening.
    signal refreshed()

    function refresh(): void {
        if (probe.running)
            return;
        probe.running = true;
    }

    // Parses an animation style ("slide", "slidevert", "slidefade 20%", …).
    function applyStyle(style: string): void {
        const parts = String(style ?? "").trim().toLowerCase().split(/\s+/);
        const kind = parts[0] || "slide";
        const percent = parts.find(part => part.endsWith("%"));
        root.fade = kind.indexOf("fade") >= 0;
        root.axis = kind.startsWith("slide") ? (kind.endsWith("vert") ? "y" : "x") : "none";
        root.distance = kind.startsWith("slidefade") && percent
            ? Math.max(0.05, Math.min(1, parseFloat(percent) / 100))
            : 1;
    }

    Process {
        id: probe
        command: ["hyprctl", "animations", "-j"]
        stdout: StdioCollector { id: probeOut }
        onExited: code => {
            if (code !== 0)
                return;
            try {
                const parsed = JSON.parse(probeOut.text);
                const animations = parsed[0] ?? [];
                const beziers = parsed[1] ?? [];
                // `workspacesIn` wins where it is set: it is the one the incoming
                // workspace, and so the incoming sheet, moves by.
                const incoming = animations.find(entry => entry?.name === "workspacesIn" && entry?.overridden);
                const workspaces = incoming ?? animations.find(entry => entry?.name === "workspaces");
                if (!workspaces)
                    return;

                root.slides = workspaces.enabled !== false;
                root.applyStyle(workspaces.style);
                // The speed is in deciseconds. Zero means "inherit", which in
                // practice is the built-in default rather than an instant switch.
                const speed = Number(workspaces.speed ?? 0);
                root.durationMs = speed > 0 ? Math.round(speed * 100) : 500;

                const curve = beziers.find(entry => entry?.name === workspaces.bezier);
                if (curve) {
                    root.curve = [Number(curve.X0), Number(curve.Y0),
                                  Number(curve.X1), Number(curve.Y1), 1, 1];
                }
                root.refreshed();
            } catch (error) {
                console.warn("[wm] could not read the workspace animation:", error);
            }
        }
    }

    // A reloaded config can change the numbers under the overlay.
    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            if (event.name === "configreloaded")
                root.refresh();
        }
    }
}
