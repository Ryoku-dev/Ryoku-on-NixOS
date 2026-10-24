pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * The dynamic-island gate the dock's phone-mirror tile reads.
 *
 * Ryoku does not ship the reference's dynamic island, so no island ever
 * owns the phone-mirror error: the tile keeps reporting failures itself.
 */
Singleton {
    id: root

    readonly property bool enabled: false

    function widgetEnabled(name: string): bool {
        return false;
    }
}
