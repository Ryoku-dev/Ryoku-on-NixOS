pragma Singleton
import QtQuick
import Quickshell
import shell.services

// The launchers RyoStore installed (launchers.json): runnable, receipt-owned
// views the launcher host joins to its catalog (lib/catalog.js withStore).
Singleton {
    id: root

    readonly property string stateRoot: index.stateRoot
    readonly property var rows: index.rows
    readonly property bool ready: index.ready

    StoreIndex {
        id: index
        category: "launchers"
    }
}
