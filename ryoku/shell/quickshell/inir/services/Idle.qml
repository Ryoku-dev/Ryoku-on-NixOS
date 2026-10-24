pragma Singleton

import QtQuick
import Quickshell
import inir.modules.common
import shell.services as Ryoku

// Idle bridge for the vendored frame. Ryoku owns the idle policy: the
// ryoku-idle daemon runs the timeouts and the shell process holds the single
// keep-awake inhibitor. The frame only reads and flips that flag through the
// reference's surface (inhibit / toggleInhibit), so no second swayidle ever
// starts beside the desktop's own.
Singleton {
    id: root

    // The reference's signal; nothing here drives it any more, but the frame
    // still connects to keep the surface intact.
    signal resumed()

    readonly property bool inhibit: Ryoku.Flags.keepAwake
    readonly property bool batteryProfileActive: !Ryoku.Battery.onAc

    function toggleInhibit(active = null): void {
        Ryoku.Flags.keepAwake = active !== null ? Boolean(active) : !Ryoku.Flags.keepAwake
    }

    function notifyResumed(): void {
        root.resumed()
    }
}
