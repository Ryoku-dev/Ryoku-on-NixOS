import QtQuick
import Quickshell

/**
 * A focus-grab compatibility component. The window-manager seam delivers
 * outside-click dismissal through layer-shell keyboard focus, so this keeps
 * the reference surface (windows/active/cleared) without a compositor hook.
 */
Item {
    id: root
    property var windows: []
    property bool active: false

    signal cleared()
}
