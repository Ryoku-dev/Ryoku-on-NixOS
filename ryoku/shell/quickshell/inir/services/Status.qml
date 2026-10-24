pragma Singleton

import QtQuick
import Quickshell

// The reference tray module exposed Status as a bare enum; the shim re-exports
// the same values (lower-cased, since QML property names may not start with a
// capital) so the frame reads them unchanged.
Singleton {
    readonly property string passive: "passive"
    readonly property string active: "active"
    readonly property string needsAttention: "needs-attention"
}
