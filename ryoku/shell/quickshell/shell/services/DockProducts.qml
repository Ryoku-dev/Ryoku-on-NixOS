pragma Singleton
import QtQuick
import Quickshell
import "lib/storeview.js" as StoreView

// The docks RyoStore installed (docks.json): each runs from its receipt-owned
// view as the dock design of its id (UniversalDockHost), picked in Edit desktop
// -> Dock like a shipped design.
Singleton {
    id: root

    readonly property var rows: index.rows
    readonly property bool ready: index.ready

    // The file URL of an installed dock's Dock.qml, "" when no valid row names
    // that id.
    function urlFor(id) {
        return StoreView.storeViewUrl(index.rows, id, index.stateRoot, "dock-views", "Dock.qml");
    }

    StoreIndex {
        id: index
        category: "docks"
    }
}
