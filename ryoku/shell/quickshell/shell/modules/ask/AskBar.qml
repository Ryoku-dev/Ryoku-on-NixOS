pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Ryoku.Ui.Singletons
import shell.services
import "../../services" as Services
import "../../components"

Scope {
    id: root

    required property var screen
    property bool active: false
    property string mode: "ask"
    property string tool: ""

    signal requestClose()
    signal modeChangeRequested(string mode)

    readonly property real s: Tokens.uiScaleFor(screen ? screen.name : "")
    readonly property var clearances: SidebarState.railClearances(screen)
    readonly property real screenWidth: screen && screen.width > 0 ? screen.width : 1280
    readonly property real screenHeight: screen && screen.height > 0 ? screen.height : 800
    readonly property real gap: Tokens.s3 * s

    // Under a bar style's seam the ask bar hangs from the style's bar like its
    // own panels, under the mark that opened it, and a chat grows down to a cap.
    readonly property bool welded: weld.welded

    readonly property real availableWidth: Math.max(1, root.welded ? screenWidth - weld.place.margin * 2
        : screenWidth - clearances.left - clearances.right - gap * 2)
    readonly property real panelWidth: Math.min(availableWidth, 720 * s)
    readonly property real panelX: (screenWidth - panelWidth) / 2
    readonly property real panelY: Math.max(clearances.top + gap, screenHeight * 0.18)
    readonly property real maximumHeight: root.welded
        ? Math.max(1, Math.min(640 * s, screenHeight - weld.place.depth - weld.place.margin))
        : Math.max(1, screenHeight - panelY - clearances.bottom - gap)
    readonly property real desiredHeight: Math.min(maximumHeight, surface.implicitHeight)
    property real presentedHeight: desiredHeight
    property real reveal: active ? 1 : 0
    property alias query: surface.query
    readonly property bool motionAllowed: !Tokens.reduceMotion && !Motion.reduce

    Behavior on reveal {
        enabled: root.motionAllowed
        NumberAnimation {
            duration: root.welded ? Motion.morph : Tokens.swap
            easing.type: root.welded ? Easing.BezierSpline : Tokens.ease
            easing.bezierCurve: root.welded ? Motion.effectsCurve : []
        }
    }


    function switchMode(next) {
        if (["ask", "chat", "tools", "web"].indexOf(next) < 0 || mode === next)
            return;
        modeChangeRequested(next);
        Qt.callLater(surface.focusField);
    }

    onActiveChanged: {
        if (active) {
            if (tool === "compress" || tool === "install")
                switchMode("tools");
            Qt.callLater(surface.focusField);
        }
    }

    Services.AskSession {
        id: session
        question: surface.query
    }

    // One full-screen surface holds the bar and the click-away area: a second
    // exclusive surface for the scrim leaves the keyboard with whichever one the
    // compositor mapped last, and Hyprland and niri disagree about which.
    PanelWindow {
        id: panel
        screen: root.screen
        visible: (root.active || root.reveal > 0.001) && !weld.remap
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        // The namespace is fixed when the layer maps, so it follows the seam the
        // bar will weld to. A welded bar takes the keyboard on demand: an
        // exclusive layer would keep the bar's marks from being pressed on
        // Hyprland.
        WlrLayershell.namespace: weld.welded ? "ryoku-weld-ask" : "ryoku-ask"
        WlrLayershell.keyboardFocus: !root.active ? WlrKeyboardFocus.None
            : root.welded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
        mask: Region {
            width: panel.width
            height: panel.height
            Region { intersection: Intersection.Subtract; width: panel.width; height: root.clearances.top }
            Region { intersection: Intersection.Subtract; y: panel.height - root.clearances.bottom; width: panel.width; height: root.clearances.bottom }
            Region { intersection: Intersection.Subtract; width: root.clearances.left; height: panel.height }
            Region { intersection: Intersection.Subtract; x: panel.width - root.clearances.right; width: root.clearances.right; height: panel.height }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.active
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: Qt.callLater(root.requestClose)
        }

        WeldedCard {
            id: weld
            screen: root.screen
            surfaceId: "ask"
            open: root.active
            hostVisible: panel.visible
            onSeamLost: root.requestClose()
            ownReveal: false
            reveal: root.reveal
            cardWidth: root.panelWidth
            cardHeight: root.presentedHeight
        }

        FocusScope {
            id: focusSurface
            parent: root.welded ? weld.slot : panel.contentItem
            x: root.welded ? 0 : root.panelX
            y: root.welded ? 0 : root.panelY
            width: root.panelWidth
            height: root.presentedHeight
            focus: root.active
            opacity: root.welded ? 1 : root.reveal
            scale: root.welded ? 1 : 0.96 + root.reveal * 0.04
            transformOrigin: Item.Top
            Keys.onEscapePressed: root.requestClose()
            onFocusChanged: if (focus) Qt.callLater(() => focusSurface.forceActiveFocus())

            // Presses on the bar stay on the bar; only the paper around it dismisses.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: event => event.accepted = true
            }

            RectangularShadow {
                anchors.fill: surface
                radius: surface.radius
                blur: 28 * root.s
                spread: 4 * root.s
                color: Qt.rgba(Tokens.keycapDark.r, Tokens.keycapDark.g, Tokens.keycapDark.b, 0.42)
                visible: root.active && !root.welded
            }

            AskSurface {
                id: surface
                anchors.fill: parent
                s: root.s
                screen: root.screen
                session: session
                active: root.active
                welded: root.welded
                mode: root.mode
                tool: root.tool
                maximumHeight: root.maximumHeight
                onRequestClose: root.requestClose()
                onModeRequested: next => root.switchMode(next)
            }
        }
    }
}
