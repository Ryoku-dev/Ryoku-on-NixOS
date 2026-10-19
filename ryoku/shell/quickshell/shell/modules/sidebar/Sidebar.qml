pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Ryoku.Ui.Singletons
import shell.services
import "../bar/framebars/RailGeometry.js" as RailGeometry
import "../../components"

Scope {
    id: root
    required property var screen
    property bool active: false
    readonly property real s: Tokens.uiScaleFor(screen ? screen.name : "")
    readonly property var clearances: SidebarState.railClearances(screen)
    readonly property real gap: Tokens.s3 * s
    readonly property real screenWidth: screen && screen.width > 0 ? screen.width : 1280
    readonly property real screenHeight: screen && screen.height > 0 ? screen.height : 800
    // The bar style's seam: the card then welds onto the bar like the style's own
    // panels and slides out from under it.
    readonly property var seam: SidebarState.seamFor(screen)
    readonly property real availableWidth: Math.max(1, seam ? screenWidth - seam.margin * 2
        : screenWidth - clearances.left - clearances.right - gap * 2)
    readonly property real availableHeight: Math.max(1, seam ? screenHeight - seam.depth - gap - clearances.bottom
        : screenHeight - clearances.top - clearances.bottom - gap * 2)
    readonly property real wantedWidth: Math.min(availableWidth, 688 * s)
    readonly property real wantedHeight: Math.min(availableHeight, chrome.fittedHeight)
    // The widget that asked for the card, in this screen's own coordinates.
    readonly property var trigger: SidebarState.triggerFor(screen)
    readonly property var fit: seam
        ? RailGeometry.seamPlacement(trigger, screenWidth, screenHeight, clearances, seam, gap,
            wantedWidth, wantedHeight)
        : RailGeometry.cardPlacement(trigger, screenWidth, screenHeight,
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
    // A welded card's window also holds its fillets beside it and a row tucked
    // under the bar, whose edge clips the card while it slides.
    readonly property bool welded: place.welded === true && !!seam
    readonly property int wing: welded ? Math.ceil(seam.fillet) : 0
    readonly property int tuck: welded ? 1 : 0
    property real reveal: active ? 1 : 0
    readonly property real travel: (cardHeight + tuck) * (1 - reveal)

    Behavior on reveal {
        enabled: !Motion.reduce && !Tokens.reduceMotion
        NumberAnimation {
            duration: root.welded ? SidebarState.motionDuration(Motion.morph)
                : root.active ? SidebarState.enterDuration : SidebarState.exitDuration
            easing.type: root.welded ? Easing.BezierSpline : Easing.Bezier
            easing.bezierCurve: root.welded ? Motion.effectsCurve
                : root.active ? SidebarState.enterCurve : SidebarState.exitCurve
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
            Region { intersection: Intersection.Subtract; x: root.panelX - root.wing; y: root.panelY - root.tuck; width: root.cardWidth + root.wing * 2; height: root.cardHeight + root.tuck }
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
        margins.top: root.insetTop - root.tuck
        margins.bottom: root.insetBottom
        margins.left: root.insetLeft - root.wing
        margins.right: root.insetRight
        implicitWidth: root.cardWidth + root.wing * 2
        implicitHeight: root.cardHeight + root.tuck
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-sidebar-left"
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        FocusScope {
            id: surface
            anchors.fill: parent
            opacity: root.reveal
            scale: root.welded ? 1 : 0.985 + root.reveal * 0.015
            transformOrigin: root.place.corner ? Item.TopLeft
                : root.place.edge === "bottom" ? Item.Bottom
                : root.place.edge === "left" ? Item.Left
                : root.place.edge === "right" ? Item.Right : Item.Top
            transform: Translate {
                readonly property real slide: (1 - root.reveal) * Tokens.s2 * root.s
                x: root.welded ? 0 : root.place.edge === "left" ? -slide : root.place.edge === "right" ? slide : 0
                y: root.welded ? -root.travel
                    : root.place.edge === "top" ? -slide : root.place.edge === "bottom" ? slide : 0
            }
            focus: root.active
            Keys.onEscapePressed: SidebarState.close(root.screen)
            onFocusChanged: if (focus) Qt.callLater(() => surface.forceActiveFocus())
            SidebarFrame { anchors.fill: parent; visible: !root.welded; s: root.s }
            WeldShape {
                visible: root.welded
                x: root.wing
                y: root.tuck
                width: root.cardWidth
                height: root.cardHeight
                fillet: root.welded ? Math.max(0, Math.min(root.seam.fillet, root.seam.fillet - root.travel)) : 0
                radius: root.welded ? root.seam.radius : 0
                role: root.welded ? root.seam.fill : "surface"
            }
            SidebarChrome {
                id: chrome
                anchors.fill: parent
                anchors.leftMargin: root.wing
                anchors.rightMargin: root.wing
                anchors.topMargin: root.tuck
                screen: root.screen
                s: root.s
                active: root.active
                onCloseRequested: SidebarState.close(root.screen)
            }
        }
    }
}
