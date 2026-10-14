pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Ryoku.Ui.Singletons

/**
 * The ii dock's compositor view, resolved through Ryoku's window-manager seam
 * so the dock behaves the same under Hyprland and niri. The reference asked
 * the Hyprland data service for monitors, the window list, the active
 * workspace and per-workspace clients; every one of those is a neutral frame
 * here, shaped like the records the copied services read.
 */
Singleton {
    id: root

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

    readonly property var windowList: {
        const ws = Wm.workspaces || [];
        const list = Wm.windows || [];
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const w = list[i];
            let full = false;
            for (let j = 0; j < ws.length; j++) {
                if (String(ws[j].id) === String(w.workspace) || ws[j].name === String(w.workspace)) {
                    full = ws[j].fullscreen === true;
                    break;
                }
            }
            out.push({
                "address": String(w.id),
                "class": w.appId || "",
                "title": w.title || "",
                "workspace": { "id": w.workspace || "" },
                "initialWorkspace": { "id": w.workspace || "" },
                "fullscreen": full,
                "floating": w.floating === true,
                "pinned": false
            });
        }
        return out;
    }

    readonly property var activeWorkspace: {
        const fw = Wm.focusedWorkspace;
        return fw ? { "id": fw.id, "name": fw.name } : { "id": "", "name": "" };
    }

    // A toplevel counts as visible when its window is on the screen the
    // compositor reports for it; the seam already keys residue to outputs.
    function toplevelOnScreen(toplevel) {
        if (!toplevel)
            return false;
        const list = Wm.windows || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].toplevel === toplevel)
                return list[i].output !== "";
        }
        return true;
    }

    function monitorHasFullscreenWindow(name) {
        return Wm.outputHasFullscreen(name);
    }

    function hyprlandClientsForWorkspace(wsId) {
        const key = String(wsId);
        const list = Wm.windows || [];
        const out = [];
        for (let i = 0; i < list.length; i++)
            if (String(list[i].workspace) === key)
                out.push(list[i]);
        return out;
    }
}
