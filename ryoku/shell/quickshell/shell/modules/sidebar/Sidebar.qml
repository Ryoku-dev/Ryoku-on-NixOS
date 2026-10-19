pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Ryoku.Ui.Singletons
import shell.services
import "../bar/framebars/RailGeometry.js" as RailGeometry

Scope {
    id: root
    required property var screen
    property bool active: false
    readonly property real s: Tokens.uiScaleFor(screen ? screen.name : "")
    readonly property var clearances: SidebarState.railClearances(screen)
    readonly property real gap: Tokens.s3 * s
    readonly property real screenWidth: screen && screen.width > 0 ? screen.width : 1280
    readonly property real screenHeight: screen && screen.height > 0 ? screen.height : 800
    readonly property real availableWidth: Math.max(1, screenWidth - clearances.left - clearances.right - gap * 2)
    readonly property real availableHeight: Math.max(1, screenHeight - clearances.top - clearances.bottom - gap * 2)
    readonly property real wantedWidth: Math.min(availableWidth, 688 * s)
    readonly property real wantedHeight: Math.min(availableHeight, chrome.fittedHeight)
    // The widget that asked for the card, in this screen's own coordinates.
    readonly property var trigger: SidebarState.triggerFor(screen)
    readonly property var fit: RailGeometry.cardPlacement(trigger, screenWidth, screenHeight,
        clearances, gap, wantedWidth, wantedHeight)
    // A closing card stays where it was while its drawers fold up.
    property var place: fit
    Binding {
        target: root
        property: "place"
        value: root.fit
        when: root.active
        restoreMode: Binding.RestoreNone
    }
    // Layer margins round and window sizes truncate, so the card and its hole in
    // the dismiss layer are both cut from these integers.
    readonly property int cardWidth: Math.floor(wantedWidth)
    readonly property int cardHeight: Math.floor(wantedHeight)
    readonly property int insetTop: place.y === "top" ? Math.round(place.top) : 0
    readonly property int insetBottom: place.y === "bottom" ? Math.round(place.bottom) : 0
    readonly property int insetLeft: place.x === "left" ? Math.round(place.left) : 0
    readonly property int insetRight: place.x === "right" ? Math.round(place.right) : 0
    readonly property int panelX: place.x === "left" ? insetLeft : screenWidth - insetRight - cardWidth
    readonly property int panelY: place.y === "top" ? insetTop : screenHeight - insetBottom - cardHeight
    property real reveal: active ? 1 : 0

    Behavior on reveal {
        enabled: !Motion.reduce && !Tokens.reduceMotion
        NumberAnimation {
            duration: root.active ? SidebarState.enterDuration : SidebarState.exitDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: root.active ? SidebarState.enterCurve : SidebarState.exitCurve
        }
    }

    // The dismiss surface never animates. Only the small corner buffer redraws.
    PanelWindow {
        id: dismiss
        screen: root.screen
        visible: root.active
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-corner-dismiss"
        // Both windows must be modal for the click-away surface to receive input.
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: Region {
            width: dismiss.width
            height: dismiss.height
            Region { intersection: Intersection.Subtract; x: root.panelX; y: root.panelY; width: root.cardWidth; height: root.cardHeight }
            Region { intersection: Intersection.Subtract; width: dismiss.width; height: root.clearances.top }
            Region { intersection: Intersection.Subtract; y: dismiss.height - root.clearances.bottom; width: dismiss.width; height: root.clearances.bottom }
            Region { intersection: Intersection.Subtract; width: root.clearances.left; height: dismiss.height }
            Region { intersection: Intersection.Subtract; x: dismiss.width - root.clearances.right; width: root.clearances.right; height: dismiss.height }
        }
        MouseArea {
            anchors.fill: parent
            focus: root.active
            Keys.onEscapePressed: SidebarState.close(root.screen)
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: Qt.callLater(() => SidebarState.close(root.screen))
        }
    }
    PanelWindow {
        id: panel
        screen: root.screen
        visible: root.active || root.reveal > 0.001
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        anchors.top: root.place.y === "top"
        anchors.bottom: root.place.y === "bottom"
        anchors.left: root.place.x === "left"
        anchors.right: root.place.x === "right"
        margins.top: root.insetTop
        margins.bottom: root.insetBottom
        margins.left: root.insetLeft
        margins.right: root.insetRight
        implicitWidth: root.cardWidth
        implicitHeight: root.cardHeight
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-sidebar-left"
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        FocusScope {
            id: surface
            anchors.fill: parent
            opacity: root.reveal
            scale: 0.985 + root.reveal * 0.015
            transformOrigin: root.place.corner ? Item.TopLeft
                : root.place.edge === "bottom" ? Item.Bottom
                : root.place.edge === "left" ? Item.Left
                : root.place.edge === "right" ? Item.Right : Item.Top
            transform: Translate {
                readonly property real slide: (1 - root.reveal) * Tokens.s2 * root.s
                x: root.place.edge === "left" ? -slide : root.place.edge === "right" ? slide : 0
                y: root.place.edge === "top" ? -slide : root.place.edge === "bottom" ? slide : 0
            }
            focus: root.active
            Keys.onEscapePressed: SidebarState.close(root.screen)
            onFocusChanged: if (focus) Qt.callLater(() => surface.forceActiveFocus())
            SidebarFrame { anchors.fill: parent; s: root.s }
            SidebarChrome {
                id: chrome
                anchors.fill: parent
                screen: root.screen
                s: root.s
                active: root.active
                onCloseRequested: SidebarState.close(root.screen)
            }
        }
    }
}
