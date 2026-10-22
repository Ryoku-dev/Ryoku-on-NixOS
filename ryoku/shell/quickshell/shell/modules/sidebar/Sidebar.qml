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
    readonly property int insetTop: storeRuns ? Math.round(storeY)
        : place.y === "top" ? Math.round(place.top) : 0
    readonly property int insetBottom: !storeRuns && place.y === "bottom" ? Math.round(place.bottom) : 0
    readonly property int insetLeft: storeRuns ? Math.round(storeX)
        : place.x === "left" ? Math.round(place.left) : 0
    readonly property int insetRight: !storeRuns && place.x === "right" ? Math.round(place.right) : 0
    readonly property int panelX: storeRuns || place.x === "left" ? insetLeft : screenWidth - insetRight - cardWidth
    readonly property int panelY: storeRuns || place.y === "top" ? insetTop : screenHeight - insetBottom - cardHeight
    // A welded card's window also holds its fillets beside it and a row tucked
    // under the bar, whose edge clips the card while it slides.
    readonly property bool welded: !storeRuns && place.welded === true && !!seam
    readonly property int wing: welded ? Math.ceil(seam.fillet) : 0
    readonly property int tuck: welded ? 1 : 0
    // A store sidebar design is drawn only off the seam: under a bar style's
    // seam the card is the welded one.
    readonly property string selectedDesign: Designs.sidebar
    readonly property string storeUrl: Designs.sidebarReady ? Designs.sidebarUrl : ""
    property string failedUrl: ""
    readonly property bool storeRuns: !seam && selectedDesign !== Designs.shipped
        && Designs.sidebarReady && storeUrl !== "" && storeUrl !== failedUrl
    readonly property var storeItem: storeLoader.status === Loader.Ready ? storeLoader.item : null
    readonly property string placement: storeRuns && storeItem
        ? normalizedPlacement(storeItem.placement) : "top-left"
    readonly property bool sidePlacement: placement === "left" || placement === "right"
    readonly property real stockWidth: Math.min(availableWidth, 688 * s)
    readonly property real stockFallbackHeight: (Tokens.s4 * 2 + Tokens.ctlH + Tokens.s1
        + Tokens.s3 + Tokens.cellH * 4) * s
    readonly property real stockHeight: Math.min(availableHeight, shippedLoader.item
        ? shippedLoader.item.fittedHeight : stockFallbackHeight)
    readonly property real wantedWidth: storeRuns
        ? Math.min(availableWidth, usableSize(storeItem ? storeItem.implicitWidth : 0, stockWidth))
        : stockWidth
    readonly property real wantedHeight: storeRuns
        ? (sidePlacement ? availableHeight
            : Math.min(availableHeight, usableSize(storeItem ? storeItem.implicitHeight : 0, stockHeight)))
        : stockHeight
    readonly property real roomX: clearances.left + gap
    readonly property real roomY: clearances.top + gap
    readonly property real storeX: placement === "top-right" || placement === "right"
        ? roomX + availableWidth - wantedWidth
        : placement === "center" ? roomX + (availableWidth - wantedWidth) / 2 : roomX
    readonly property real storeY: placement === "center"
        ? roomY + (availableHeight - wantedHeight) / 2 : roomY
    readonly property int panelTransformOrigin: placement === "top-right" ? Item.TopRight
        : placement === "left" ? Item.Left
        : placement === "right" ? Item.Right
        : placement === "center" ? Item.Center : Item.TopLeft
    readonly property real panelSlideX: placement === "left" ? -Tokens.s2 * s
        : placement === "right" ? Tokens.s2 * s : 0
    readonly property real panelSlideY: sidePlacement ? 0 : -Tokens.s2 * s
    property real reveal: active ? 1 : 0
    readonly property real travel: (cardHeight + tuck) * (1 - reveal)

    function normalizedPlacement(value) {
        const candidate = String(value ?? "");
        return candidate === "top-right" || candidate === "left" || candidate === "right"
            || candidate === "center" ? candidate : "top-left";
    }

    function usableSize(value, fallback) {
        const candidate = Number(value);
        return Number.isFinite(candidate) && candidate > 0 ? candidate : fallback;
    }

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
        // Under a seam they take the keyboard on demand instead: an exclusive
        // layer would keep the bar's marks from being pressed on Hyprland.
        WlrLayershell.keyboardFocus: !root.active ? WlrKeyboardFocus.None
            : root.seam ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
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
        anchors.top: root.storeRuns || root.place.y === "top"
        anchors.bottom: !root.storeRuns && root.place.y === "bottom"
        anchors.left: root.storeRuns || root.place.x === "left"
        anchors.right: !root.storeRuns && root.place.x === "right"
        margins.top: root.insetTop - root.tuck
        margins.bottom: root.insetBottom
        margins.left: root.insetLeft - root.wing
        margins.right: root.insetRight
        implicitWidth: root.cardWidth + root.wing * 2
        implicitHeight: root.cardHeight + root.tuck
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: root.seam ? "ryoku-weld-controls" : "ryoku-sidebar-left"
        WlrLayershell.keyboardFocus: !root.active ? WlrKeyboardFocus.None
            : root.seam ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

        FocusScope {
            id: surface
            anchors.fill: parent
            opacity: root.reveal
            scale: root.welded ? 1 : 0.985 + root.reveal * 0.015
            transformOrigin: root.storeRuns ? root.panelTransformOrigin
                : root.place.corner ? Item.TopLeft
                : root.place.edge === "bottom" ? Item.Bottom
                : root.place.edge === "left" ? Item.Left
                : root.place.edge === "right" ? Item.Right : Item.Top
            transform: Translate {
                readonly property real slide: (1 - root.reveal) * Tokens.s2 * root.s
                x: root.storeRuns ? (1 - root.reveal) * root.panelSlideX
                    : root.welded ? 0 : root.place.edge === "left" ? -slide : root.place.edge === "right" ? slide : 0
                y: root.storeRuns ? (1 - root.reveal) * root.panelSlideY
                    : root.welded ? -root.travel
                    : root.place.edge === "top" ? -slide : root.place.edge === "bottom" ? slide : 0
            }
            focus: root.active
            Keys.onEscapePressed: SidebarState.close(root.screen)
            onFocusChanged: if (focus) Qt.callLater(() => surface.forceActiveFocus())

            Loader {
                id: shippedLoader
                anchors.fill: parent
                active: !root.storeRuns
                sourceComponent: Item {
                    readonly property real fittedHeight: chrome.fittedHeight

                    SidebarFrame {
                        anchors.fill: parent
                        visible: !root.welded
                        s: root.s
                    }
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

            Loader {
                id: storeLoader
                anchors.fill: parent
                active: root.storeRuns
                asynchronous: true
                visible: root.storeRuns
                readonly property string url: root.storeUrl

                onUrlChanged: storeLoader.load()
                Component.onCompleted: storeLoader.load()

                function load() {
                    if (storeLoader.url === "") {
                        storeLoader.source = "";
                        return;
                    }
                    storeLoader.setSource(storeLoader.url, {
                        screen: root.screen,
                        us: root.s,
                        active: root.active,
                        availableWidth: root.availableWidth,
                        availableHeight: root.availableHeight
                    });
                }

                onStatusChanged: {
                    if (storeLoader.status !== Loader.Error || storeLoader.url === ""
                            || root.failedUrl === storeLoader.url)
                        return;
                    console.warn("sidebar: the store sidebar " + root.selectedDesign
                        + " did not load; drawing the Ryoku sidebar");
                    root.failedUrl = storeLoader.url;
                }
            }

            Binding {
                target: storeLoader.item
                property: "screen"
                value: root.screen
                when: storeLoader.status === Loader.Ready && storeLoader.item !== null
                restoreMode: Binding.RestoreNone
            }
            Binding {
                target: storeLoader.item
                property: "us"
                value: root.s
                when: storeLoader.status === Loader.Ready && storeLoader.item !== null
                restoreMode: Binding.RestoreNone
            }
            Binding {
                target: storeLoader.item
                property: "active"
                value: root.active
                when: storeLoader.status === Loader.Ready && storeLoader.item !== null
                restoreMode: Binding.RestoreNone
            }
            Binding {
                target: storeLoader.item
                property: "availableWidth"
                value: root.availableWidth
                when: storeLoader.status === Loader.Ready && storeLoader.item !== null
                restoreMode: Binding.RestoreNone
            }
            Binding {
                target: storeLoader.item
                property: "availableHeight"
                value: root.availableHeight
                when: storeLoader.status === Loader.Ready && storeLoader.item !== null
                restoreMode: Binding.RestoreNone
            }
            Connections {
                target: storeLoader.status === Loader.Ready ? storeLoader.item : null
                ignoreUnknownSignals: true
                function onCloseRequested() {
                    SidebarState.close(root.screen);
                }
            }
        }
    }
}
