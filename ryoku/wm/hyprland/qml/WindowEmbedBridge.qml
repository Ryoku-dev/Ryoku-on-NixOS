pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Provider bridge for window embedding: holding one window pinned to a layer
// surface's screen and corner, so a desktop widget can cut a hole in itself and
// show that window through it. The neutral loader (shell/components/WindowEmbed)
// binds nothing and calls embed()/park() and listens for layoutChanged; the
// whole compositor-specific dance lives here.
//
// Hyprland's IPC takes one Lua expression, so everything a placement does
// travels as a single call rather than four round trips. The window is found by
// title and the panel by its layer namespace, both handed in by the caller.
Item {
    id: root

    /// The layout moved under an embedded window: a workspace switch, a monitor
    /// change, or the panel's layer surfacing or closing. The caller re-places.
    signal layoutChanged()

    /** Pins the window titled `title` into the rectangle (x,y,w,h) inside the
     *  layer named `layerNamespace`, on that layer's monitor, with `cornerRadius`
     *  applied. Size lands before position: an exact resize keeps the window
     *  centred on where it was, so a move first would correct a rectangle about
     *  to shift again. */
    function embed(title: string, layerNamespace: string, x: real, y: real, w: real, h: real, cornerRadius: int): void {
        const ops = findWindow(title)
            + findPanel(layerNamespace)
            + attachToPanelScreen()
            + `hl.dispatch(hl.dsp.window.resize({window=w,x=${Math.round(w)},y=${Math.round(h)},exact=true})) `
            + `hl.dispatch(hl.dsp.window.move({window=w,x=lx+${Math.round(x)},y=ly+${Math.round(y)},exact=true})) `
            + `if not w.pinned then hl.dispatch(hl.dsp.window.pin({window=w})) end `
            + `hl.dispatch(hl.dsp.window.set_prop({window=w,rounding=${Math.max(0, cornerRadius)}})) `;
        Hyprland.dispatch(wrap(ops));
    }

    /** Lets go of the embedded window and moves it off every screen, so it stops
     *  encoding for a frame that closed. Unpinning first: a pinned window belongs
     *  to every workspace at once and would otherwise keep following the user. */
    function park(title: string, offscreen: int): void {
        const ops = findWindow(title)
            + `if w.pinned then hl.dispatch(hl.dsp.window.pin({window=w})) end `
            + `hl.dispatch(hl.dsp.window.move({window=w,x=${offscreen},y=${offscreen},exact=true})) `;
        Hyprland.dispatch(wrap(ops));
    }

    function wrap(ops: string): string {
        return `(function() ${ops} return hl.dsp.no_op() end)()`;
    }

    function findWindow(title: string): string {
        return `local t="${title}" local w `
            + `for _,v in ipairs(hl.get_windows()) do if v.title==t then w=v end end `
            + `if not w then return hl.dsp.no_op() end `;
    }

    /** The panel's layer surface: its own position is what the cut-out's
     *  coordinates are relative to, and a surface that is not mapped has no
     *  cut-out to sit under. */
    function findPanel(layerNamespace: string): string {
        return `local ns="${layerNamespace}" local lx,ly,mon `
            + `for _,l in ipairs(hl.get_layers()) do if l.namespace==ns then lx=l.x ly=l.y mon=l.monitor end end `
            + `if not lx then return hl.dsp.no_op() end `;
    }

    /** Pinned windows belong to one monitor, so the window has to reach the
     *  panel's monitor before it is pinned to it. */
    function attachToPanelScreen(): string {
        return `local ws=mon and mon.active_workspace or hl.get_active_workspace() `
            + `if ws and (not w.workspace or w.workspace.id~=ws.id) then `
            + `hl.dispatch(hl.dsp.window.move({window=w,workspace=ws,follow=false})) end `;
    }

    // A pinned window follows the workspace, but it lands wherever it was left
    // when the monitor's layout shifts under it.
    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            switch (event.name) {
            case "workspace":
            case "focusedmon":
            case "openlayer":
            case "closelayer":
            case "monitoradded":
            case "monitorremoved":
                root.layoutChanged();
            }
        }
    }
}
