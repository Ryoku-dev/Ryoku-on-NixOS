pragma Singleton

import QtQuick
import Quickshell
import stage as Stage
import stage.modules.ii.editMode as StageEdit

/**
 * Where the Stage Editor draws the edited monitor's desktop.
 *
 * The editor shrinks the desktop into a card. The bar and the dock are part of
 * that desktop, so their windows draw themselves into the same card, on the
 * same matrix the desktop uses: what the card shows is what the desktop will
 * look like. Off the edited monitor, and outside the mode, every answer here
 * is the identity.
 */
Singleton {
    id: root

    readonly property matrix4x4 identity: Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)

    function framing(screenName: string): bool {
        return screenName !== "" && Stage.GlobalStates.editModeMonitor === screenName
            && (Stage.GlobalStates.editMode || Stage.GlobalStates.editProgress > 0);
    }

    // The desktop's matrix for a window whose origin sits at (originX,
    // originY) on a screen of the given size: screen space in, back out to
    // the window's own coordinates.
    function matrixFor(screenName: string, screenWidth: real, screenHeight: real, originX: real, originY: real): matrix4x4 {
        if (!root.framing(screenName))
            return root.identity;
        const m = StageEdit.EditModeInsets.editMatrixFor(screenName, screenWidth, screenHeight,
            Stage.GlobalStates.editProgress, Stage.GlobalStates.editDrawerProgress);
        const s = m.m11;
        const ox = originX || 0;
        const oy = originY || 0;
        return Qt.matrix4x4(
            s, 0, 0, m.m14 + (s - 1) * ox,
            0, s, 0, m.m24 + (s - 1) * oy,
            0, 0, 1, 0,
            0, 0, 0, 1);
    }

    // A rect in the window's coordinates, where the matrix draws it: what an
    // input mask has to follow so the framed surface stays clickable where it
    // is seen and click-through everywhere else.
    function mapRect(screenName: string, screenWidth: real, screenHeight: real, originX: real, originY: real, rect: rect): rect {
        const m = root.matrixFor(screenName, screenWidth, screenHeight, originX, originY);
        return Qt.rect(m.m11 * rect.x + m.m14, m.m22 * rect.y + m.m24, m.m11 * rect.width, m.m22 * rect.height);
    }
}
