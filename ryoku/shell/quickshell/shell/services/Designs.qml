pragma Singleton
import QtQuick
import Quickshell
import "lib/storeview.js" as StoreView

// The design each Ryoku-owned overlay draws (shell.json designs.*): the OSD,
// the notification card and the Super+Esc sidebar. "ryoku" is the shipped
// design of each; any other id names a design RyoStore installed, which runs
// from its receipt-owned view. A saved store design waits for its index
// (ready) so the shipped design never shows first and then swaps.
Singleton {
    id: root

    readonly property string shipped: "ryoku"

    readonly property string osd: root.pick("osd")
    readonly property string notification: root.pick("notification")
    readonly property string sidebar: root.pick("sidebar")

    readonly property bool osdReady: root.osd === root.shipped || osds.ready
    readonly property bool notificationReady: root.notification === root.shipped || notifications.ready
    readonly property bool sidebarReady: root.sidebar === root.shipped || sidebars.ready

    // "" while the shipped design is worn, or when no valid installed row
    // names the saved id: the host then draws its own design.
    readonly property string osdUrl: root.osd === root.shipped ? ""
        : StoreView.storeViewUrl(osds.rows, root.osd, osds.stateRoot, "osd-views", "Osd.qml")
    readonly property string notificationUrl: root.notification === root.shipped ? ""
        : StoreView.storeViewUrl(notifications.rows, root.notification, notifications.stateRoot,
            "notification-views", "Card.qml")
    readonly property string sidebarUrl: root.sidebar === root.shipped ? ""
        : StoreView.storeViewUrl(sidebars.rows, root.sidebar, sidebars.stateRoot, "sidebar-views", "Sidebar.qml")

    function pick(key) {
        const designs = Config.designs;
        const value = designs && typeof designs[key] === "string" ? designs[key] : "";
        return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value) ? value : root.shipped;
    }

    StoreIndex {
        id: osds
        category: "osds"
    }
    StoreIndex {
        id: notifications
        category: "notifications"
    }
    StoreIndex {
        id: sidebars
        category: "sidebars"
    }
}
