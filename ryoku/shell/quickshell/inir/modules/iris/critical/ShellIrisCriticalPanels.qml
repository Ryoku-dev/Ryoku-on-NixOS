pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import inir.modules.common
import inir.modules.iris.bar
import inir.modules.iris.frame
import inir.modules.closeConfirm
import inir.modules.regionSelector

Item {
    id: root

    component CriticalPanelLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready
            && (Config.options?.enabledPanels ?? []).includes(identifier)
            && extraCondition
    }

    LazyLoader {
        active: Config.ready
        component: IrisReservations {}
    }

    CriticalPanelLoader {
        identifier: "irisBar"
        component: IrisBar {}
    }

    // Always-on IPC hosts: the close-window confirmation and the region-capture
    // router (its `region` IPC target is what the compositor keybinds reach).
    LazyLoader {
        active: Config.ready
        component: CloseConfirm {}
    }

    LazyLoader {
        active: Config.ready
        component: RegionSelectorRouter {}
    }
}
