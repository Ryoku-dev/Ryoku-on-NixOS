pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."

/**
 * Visible content of the shell's own surfaces, for the region selector.
 *
 * Most overlays (cheatsheet, notification popups, island, sidebars…) are
 * full-screen layer surfaces that draw one card in the middle, so the surface
 * geometry says nothing about what is on screen. Each such surface drops a
 * `ShellRegionTarget` on its card; `freeze()` records where every visible card
 * is, in global logical coordinates.
 *
 * Frozen once per capture, not read live: opening the selector takes keyboard
 * focus, and focus-grabbed overlays close (and unregister) right after.
 */
Singleton {
    id: root

    property list<QtObject> targets: []
    // [{ label, screen, at: [x, y], size: [w, h] }] — global logical coords.
    property var frozen: []

    function add(target) {
        if (root.targets.indexOf(target) < 0)
            root.targets = [...root.targets, target];
    }

    function remove(target) {
        root.targets = root.targets.filter(t => t !== target && t !== null);
    }

    function effectiveOpacity(item) {
        let o = 1;
        for (let it = item; it; it = it.parent)
            o *= it.opacity;
        return o;
    }

    // Layer surfaces do not know their global origin. Qt exposes each output's
    // global origin, which is exact for the full-screen surfaces registered here.
    function windowOrigin(win, screenName, namespace) {
        const output = (Quickshell.screens || []).find(candidate => candidate.name === screenName);
        return [output?.x ?? 0, output?.y ?? 0];
    }

    function freeze() {
        const out = [];
        for (const t of root.targets) {
            const item = t?.target;
            if (!t || !t.enabled || !item || !item.visible || item.width < 8 || item.height < 8)
                continue;
            if (root.effectiveOpacity(item) < 0.05)
                continue;
            const win = item.QsWindow?.window;
            const screenName = win?.screen?.name ?? "";
            if (!win || !win.visible || screenName.length === 0)
                continue;
            // Both corners, so scaled/transformed cards keep their real extent.
            const p1 = item.mapToItem(null, 0, 0);
            const p2 = item.mapToItem(null, item.width, item.height);
            const origin = root.windowOrigin(win, screenName, t.namespace);
            const x = Math.min(p1.x, p2.x), y = Math.min(p1.y, p2.y);
            out.push({
                label: t.label,
                screen: screenName,
                at: [Math.round(origin[0] + x), Math.round(origin[1] + y)],
                size: [Math.round(Math.abs(p2.x - p1.x)), Math.round(Math.abs(p2.y - p1.y))]
            });
        }
        root.frozen = out;
    }
}
