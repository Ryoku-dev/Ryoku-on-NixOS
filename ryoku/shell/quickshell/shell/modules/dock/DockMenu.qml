pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import shell.services as Svc
import Ryoku.Ui.Singletons
import "../desktop"
import "../desktop/Singletons"

// Right-click context menu for a dock item, on the shared desktop-menu family:
// open / new window, pin or unpin (reflecting the current pin state), and close
// when the app is running. The Dock singleton owns the target and the actions;
// this only renders the rows in the paper-and-ink menu idiom -- a lifted plate,
// ink-washed MenuRows, no colour -- so a dock menu reads as one surface with the
// desktop's right-click menu instead of its own card.
Item {
    id: menu

    // A MenuRow finds its enclosing menu by this marker to close on trigger.
    readonly property bool ryoMenu: true

    readonly property bool pinned: Svc.Dock.menuPinned
    readonly property int count: Svc.Dock.menuCount

    readonly property var rows: {
        const r = [];
        r.push({ key: "open", icon: "launch", label: menu.count > 0 ? I18n.tr("New window") : I18n.tr("Open") });
        r.push({ key: "pin", icon: menu.pinned ? "keep_off" : "keep", label: menu.pinned ? I18n.tr("Unpin") : I18n.tr("Pin") });
        if (menu.count > 0)
            r.push({ key: "close", icon: "close", label: I18n.tr("Close") });
        return r;
    }

    function close() { Svc.Dock.closeMenu(); }
    function act(key) {
        if (key === "open")
            Svc.Dock.menuActOpen();
        else if (key === "pin")
            Svc.Dock.menuActPin();
        else
            Svc.Dock.menuActClose();
    }

    implicitWidth: 196
    implicitHeight: card.height

    // soft drop shadow: the menu genuinely floats over the desktop.
    MultiEffect {
        source: card
        anchors.fill: card
        visible: !Performance.shadowsDisabled
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 1.0
        shadowVerticalOffset: 12
        blurMax: 48
        autoPaddingEnabled: true
    }

    Rectangle {
        id: card
        width: parent.width
        height: col.implicitHeight + Theme.s4
        radius: Theme.menuRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        // swallow stray clicks on the plate so they never reach the dismiss layer.
        MouseArea { anchors.fill: parent }

        Column {
            id: col
            x: Theme.s2
            y: Theme.s2
            width: parent.width - Theme.s2 * 2
            spacing: Theme.s1

            Repeater {
                model: menu.rows
                delegate: MenuRow {
                    required property var modelData
                    icon: modelData.icon
                    label: modelData.label
                    onTriggered: menu.act(modelData.key)
                }
            }
        }
    }
}
