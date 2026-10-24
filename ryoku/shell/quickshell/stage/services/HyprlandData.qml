pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Ryoku.Ui.Singletons

// The Stage Editor's view of the compositor's monitors, resolved through Ryoku's
// window-manager seam so the editor is compositor-agnostic (it reads the same
// under Hyprland and niri). The reference's Edit Mode asked the Hyprland data
// service for two things: which monitor hosts a special workspace (so the chrome
// drops under it) and a monitor's make/model for a display name. Both come from
// the seam's output and workspace frames here. See docs/stage.md.
Singleton {
    id: root

    // One entry per output, shaped like the reference's monitor records so the
    // copied chrome reads it unchanged: name, the active workspace, and the
    // special workspace shown over the desktop (name "" when none).
    readonly property var monitors: {
        const outs = Wm.outputs || [];
        const ws = Wm.workspaces || [];
        const out = [];
        for (let i = 0; i < outs.length; i++) {
            const o = outs[i];
            let specialName = "";
            for (let j = 0; j < ws.length; j++) {
                const w = ws[j];
                if (w.special === true && w.active === true
                        && (w.output === "" || w.output === o.name)) {
                    specialName = w.name;
                    break;
                }
            }
            out.push({
                "name": o.name,
                "model": o.model ?? "",
                "make": o.make ?? "",
                "activeWorkspace": { "id": o.activeWorkspace ?? "" },
                "specialWorkspace": { "name": specialName }
            });
        }
        return out;
    }

    function monitorHasFullscreenWindow(name) {
        return Wm.outputHasFullscreen(name);
    }
}
