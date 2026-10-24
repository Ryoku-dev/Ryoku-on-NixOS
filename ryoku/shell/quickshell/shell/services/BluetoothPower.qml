pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

Singleton {
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property bool available: Bluetooth.defaultAdapter !== null

    function setEnabled(on: bool): void {
        if (!Bluetooth.defaultAdapter)
            return;
        Quickshell.execDetached(["ryoku-bluetooth-power", on ? "on" : "off"]);
    }

    function toggle(): void {
        setEnabled(!enabled);
    }
}
