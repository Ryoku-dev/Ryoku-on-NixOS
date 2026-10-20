import QtQuick
import Quickshell
import Ryoku.Ui.Singletons
import shell.services
import "../modules/bar/framebars/RailGeometry.js" as RailGeometry

// A panel welded onto a bar's seam inside a window that covers the whole
// screen. It hangs flush from the bar's edge under the widget that asked for it
// (centred without one) and is cut there while it slides out from under the
// bar, so the window needs ExclusionMode.Ignore to start at the top of the
// screen. Its fillets swallow presses like the panel. While the window is up
// the seam and the trigger hold still, so a panel that closes keeps its place
// and another panel's trigger never moves it; a hidden window follows them.
Item {
    id: root

    property var screen: null
    // The bus id the panel opens under ("launcher", "clipboard", "ask").
    property string surfaceId: ""
    property bool open: false
    property bool hostVisible: false
    property real cardWidth: 0
    property real cardHeight: 0
    // A host that animates its own reveal binds it here and turns this off.
    property bool ownReveal: true
    property real reveal: root.open ? 1 : 0

    // The seam went away under an open panel, so its bar has stepped aside.
    signal seamLost()

    Behavior on reveal {
        enabled: root.ownReveal && root.welded
        NumberAnimation {
            duration: (Motion.reduce || Tokens.reduceMotion) ? 0 : Motion.morph
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.effectsCurve
        }
    }

    readonly property string screenName: root.screen ? root.screen.name : ""
    property var place: SidebarState.seamFor(root.screen)
    property var trigger: ShellState.weldTriggerFor(root.screenName, root.surfaceId)
    Binding {
        target: root
        property: "place"
        value: SidebarState.seamFor(root.screen)
        when: !root.hostVisible
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "trigger"
        value: ShellState.weldTriggerFor(root.screenName, root.surfaceId)
        when: !root.hostVisible
        restoreMode: Binding.RestoreNone
    }
    readonly property bool welded: !!root.place
    readonly property bool seamLive: !!SidebarState.seamFor(root.screen)
    // Hyprland gives an on-demand layer the keyboard only when it maps, and a
    // layer keeps the namespace it mapped with. So a panel reopened while its
    // window is still up has the host hide the window for a moment, and it
    // maps again with the seam and the trigger as they are then.
    property bool remap: false
    onOpenChanged: if (root.open && root.hostVisible && (root.welded || root.seamLive)) {
        root.remap = true;
        Qt.callLater(() => root.remap = false);
    }
    onSeamLiveChanged: if (!root.seamLive && root.welded && root.open) root.seamLost()

    readonly property real fillet: root.welded ? root.place.fillet : 0
    readonly property real cardX: root.welded
        ? RailGeometry.seamLeft(root.trigger ? root.trigger.x + root.trigger.width / 2 : root.width / 2,
            root.cardWidth, root.width, root.place.margin)
        : 0
    readonly property real travel: (root.cardHeight + 1) * (1 - Math.min(1, root.reveal))
    // Only a welded reveal is animated, so this is the slide while welded and
    // the open state otherwise; it does not read `welded`, which the host's
    // visibility latches.
    readonly property bool moving: root.reveal > 0.001
    readonly property alias slot: slot
    default property alias body: slot.data

    // The host window's input while welded: the bar above the seam stays the
    // bar's, so a press on another of its marks reaches it.
    readonly property Region inputMask: Region {
        width: root.width
        height: root.height
        Region {
            intersection: Intersection.Subtract
            width: root.width
            height: root.welded ? root.place.depth : 0
        }
    }

    anchors.fill: parent
    visible: root.welded

    Item {
        id: cut

        y: root.welded ? root.place.depth - 1 : 0
        width: parent.width
        height: Math.max(0, parent.height - y)
        clip: true
        visible: root.moving

        WeldShape {
            x: root.cardX
            y: 1 - root.travel
            width: root.cardWidth
            height: root.cardHeight
            opacity: root.reveal
            fillet: Math.max(0, Math.min(root.fillet, root.fillet - root.travel))
            radius: root.welded ? root.place.radius : 0
            role: root.welded ? root.place.fill : "surface"
        }

        MouseArea {
            x: root.cardX - root.fillet
            y: 1 - root.travel
            width: root.cardWidth + root.fillet * 2
            height: root.fillet + 1
            acceptedButtons: Qt.AllButtons
        }

        Item {
            id: slot

            x: root.cardX
            y: 1 - root.travel
            width: root.cardWidth
            height: root.cardHeight
            opacity: root.reveal
        }
    }
}
