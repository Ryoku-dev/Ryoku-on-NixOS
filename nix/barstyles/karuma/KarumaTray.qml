pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "TrayMenuGroup.js" as Group

/*
 * App tray 駐: the arrow that reveals the apps running in the background.
 *
 * One component serves both renderers. BarSurface lays it out as a row and
 * RailSurface as a column (`vertical`); nothing is rotated except the arrow
 * glyph, so the icons and their hit targets stay upright.
 *
 * Collapsed, only the arrow shows. Clicking it slides the StatusNotifier icons
 * out of it (the arrow keeps its colours either way). Per icon: left click activates (or opens the menu for menu-only
 * apps), middle click is the secondary action, right click opens the app's own
 * menu (KarumaTrayMenu, styled like the hub sheets), and the wheel scrolls (volume-style tray apps).
 *
 * The module has nothing to show while no application owns a tray icon, so it
 * hides itself (`shown`) and takes no room in its lane.
 */
Item {
    id: tray

    // Karuma palette (KarumaPalette.qml) and the surface's scale factor.
    property var pal: null
    property real unit: 1
    property real innerCorner: 6
    property bool live: true
    // Rail mode: arrow and icons stack top to bottom.
    property bool vertical: false
    // "top" | "bottom" | "left" | "right": decides which way menus open (inward).
    property string edge: "top"
    property bool expanded: false

    function px(v) { return Math.round(v * tray.unit) }

    readonly property int count: SystemTray.items.values.length
    readonly property bool shown: count > 0

    readonly property int cell: px(26)
    readonly property int iconPx: px(16)
    readonly property int spacing: px(2)

    readonly property int menuEdge: edge === "top" ? Edges.Bottom
        : edge === "bottom" ? Edges.Top
        : edge === "left" ? Edges.Right : Edges.Left

    // The drawer is as long as its icons while open, and zero while closed.
    readonly property real drawerFull: count * cell + Math.max(0, count - 1) * spacing
    property real drawerSize: expanded ? drawerFull : 0
    Behavior on drawerSize {
        enabled: tray.live
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
    }

    // Collapse by itself once the last icon is gone.
    onCountChanged: if (count === 0) expanded = false
    // A menu never outlives the icons it belongs to.
    onExpandedChanged: if (!expanded) Group.closeCurrent()

    implicitWidth: vertical ? cell : cell + (drawerSize > 0 ? spacing + drawerSize : 0)
    implicitHeight: vertical ? cell + (drawerSize > 0 ? spacing + drawerSize : 0) : cell

    // ------------------------------------------------------------ the arrow
    Rectangle {
        id: arrow
        // On a rail the column is centred in whatever width the lane gives it.
        x: tray.vertical ? Math.round((tray.width - width) / 2) : 0
        y: 0
        width: tray.cell
        height: tray.cell
        radius: Math.min(tray.innerCorner, width / 2)
        antialiasing: true
        // The button keeps its colours whether the tray is open or closed. Hover
        // only adds the palette's soft hover fill, never the solid inversion.
        color: arrowHover.hovered ? tray.pal.hover : "transparent"
        border.width: 1.5
        border.color: arrowHover.hovered ? tray.pal.lineStrong : tray.pal.line
        Behavior on color { enabled: tray.live; ColorAnimation { duration: 140 } }
        Behavior on border.color { enabled: tray.live; ColorAnimation { duration: 140 } }

        Text {
            anchors.centerIn: parent
            // Points the way the icons will slide out; turns back when open.
            text: "\u203A"
            color: tray.pal.inkMuted
            font.family: tray.pal.mono
            font.weight: Font.Medium
            font.pixelSize: tray.px(15)
            rotation: tray.vertical ? (tray.expanded ? 270 : 90) : (tray.expanded ? 180 : 0)
            Behavior on rotation { enabled: tray.live; NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
        }

        HoverHandler { id: arrowHover }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: tray.expanded = !tray.expanded
        }
    }

    // ------------------------------------------------------------ the drawer
    Item {
        id: drawer
        x: tray.vertical ? Math.round((tray.width - width) / 2) : arrow.width + (tray.drawerSize > 0 ? tray.spacing : 0)
        y: tray.vertical ? arrow.height + (tray.drawerSize > 0 ? tray.spacing : 0) : 0
        width: tray.vertical ? tray.cell : tray.drawerSize
        height: tray.vertical ? tray.drawerSize : tray.cell
        clip: true
        visible: tray.drawerSize > 0.5
        opacity: tray.drawerFull > 0 ? Math.min(1, tray.drawerSize / tray.drawerFull * 1.4) : 0

        Grid {
            columns: tray.vertical ? 1 : Math.max(1, tray.count)
            rows: tray.vertical ? Math.max(1, tray.count) : 1
            spacing: tray.spacing

            Repeater {
                model: SystemTray.items

                delegate: Item {
                    id: slot
                    required property var modelData
                    width: tray.cell
                    height: tray.cell

                    readonly property string label: String(modelData.title || modelData.tooltipTitle || modelData.id || "")

                    Rectangle {
                        anchors.fill: parent
                        radius: Math.min(tray.innerCorner, width / 2)
                        color: tray.pal.lineSoft
                        opacity: slotHover.hovered ? 1 : 0
                        Behavior on opacity { enabled: tray.live; NumberAnimation { duration: 120 } }
                    }

                    IconImage {
                        id: glyph
                        anchors.centerIn: parent
                        implicitSize: tray.iconPx
                        source: slot.modelData.icon
                        mipmap: true
                        visible: status === Image.Ready
                    }

                    // Apps whose icon cannot be resolved still get a mark.
                    Text {
                        anchors.centerIn: parent
                        visible: !glyph.visible
                        text: slot.label.length > 0 ? slot.label.charAt(0).toUpperCase() : "\u30FB"
                        color: tray.pal.inkMuted
                        font.family: tray.pal.text
                        font.pixelSize: tray.px(12)
                    }

                    KarumaTrayMenu {
                        id: menu
                        pal: tray.pal
                        unit: tray.unit
                        anchorItem: slot
                        edges: tray.menuEdge
                        rootMenu: slot.modelData.menu
                    }

                    HoverHandler { id: slotHover }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            const it = slot.modelData;
                            if (mouse.button === Qt.RightButton) {
                                if (it.hasMenu) menu.open();
                            } else if (mouse.button === Qt.MiddleButton) {
                                it.secondaryActivate();
                            } else if (it.onlyMenu && it.hasMenu) {
                                menu.open();
                            } else {
                                it.activate();
                            }
                        }
                        onWheel: wheel => {
                            const dy = wheel.angleDelta.y;
                            const dx = wheel.angleDelta.x;
                            if (dy !== 0) slot.modelData.scroll(dy, false);
                            if (dx !== 0) slot.modelData.scroll(dx, true);
                        }
                    }
                }
            }
        }
    }
}
