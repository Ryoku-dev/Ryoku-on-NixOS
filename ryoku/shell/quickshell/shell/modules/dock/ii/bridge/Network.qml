pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import shell.services as RyokuNet
import ".."

/**
 * The ii dock's network view.
 *
 * The reference asked its own Network service for a wired flag and a lowercase
 * wifi status; Ryoku's shell service reports the same facts through `kind` and
 * `wifiConnectivity`. This forwards so the Drive backup's metered-connection
 * guard reads the real link instead of the stage's placeholder.
 */
Singleton {
    id: root

    readonly property bool ethernet: RyokuNet.Network.kind === "ethernet"
    readonly property bool wifiEnabled: RyokuNet.Network.wifiRadio
    readonly property var active: RyokuNet.Network.wifi
    readonly property string wifiStatus: {
        const c = String(RyokuNet.Network.wifiConnectivity ?? "").toLowerCase();
        return c === "connected" ? "connected" : c;
    }
}
