pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Ryoku.Ui.Singletons
import "Singletons"
import "../../services/lib/screens.js" as Screens
import "../../components" as C

/**
 * Ryoku workspace overview: a full-screen expo, migrated to a per-monitor module
 * entry the single resident shell instantiates once per screen. The compositor
 * blurs the desktop behind the "overview" layer (a compositor rule keyed on the
 * layer namespace), so only the workspace cells and their live
 * window previews read on top. This screen shows its own workspaces as scaled
 * mini-desktops; only the focused monitor grabs the keyboard. Click a cell to
 * switch, click a window to focus, drag a window onto another cell to move it,
 * scroll or Tab/arrows to cycle, Esc or click-out to dismiss.
 *
 * `active` drives the reveal and window mapping; the controller binds it to this
 * monitor's ShellState.overviewOpen. `screen` is the monitor this surface draws
 * on, injected by the per-screen Variants in shell.qml.
 */
Scope {
    id: root

    // The monitor this overview surface draws on, injected per-screen by shell.qml.
    property var screen: null

    // Reveal input the controller binds to this monitor's ShellState.overviewOpen.
    property bool active: false

    // Close request (Esc / click-out). The controller resets overviewOpen; we
    // never assign `active` here, which would destroy its binding to the flag
    // and leave the overview permanently unable to reopen.
    signal requestClose()

    function hide() {
        root.requestClose();
    }

    // The shell draws its own overview only where the compositor lacks a native
    // one and exposes window geometry to place the previews.
    readonly property bool available: !Wm.caps.nativeOverview && Wm.caps.windowGeometry

    readonly property string focusedMon: Wm.focusedOutput

    PanelWindow {
        id: win
        readonly property real s: Screens.monitorScale(root.screen, Wm.outputScale(root.screen ? root.screen.name : ""), 1.25) * Math.max(0.8, Math.min(1.4, Config.fontScale)) * Tokens.uiScaleFor(root.screen ? root.screen.name : "")
        readonly property bool isFocused: !root.focusedMon || root.focusedMon === (root.screen ? root.screen.name : "")
        readonly property bool shown: root.active && root.available
        // Under a bar style's seam the overview is a strip of cells hanging
        // from the bar like the style's own panels, not a full-screen expo.
        readonly property bool welded: weld.welded

        screen: root.screen
        visible: (shown || closing.running || weld.moving) && !weld.remap
        mask: win.welded ? weld.inputMask : null
        color: "transparent"
        // A welded strip needs the window to start at the top of the screen;
        // the expo stays clear of the bars' reserved edges.
        exclusionMode: win.welded ? ExclusionMode.Ignore : ExclusionMode.Normal
        // The namespace is fixed when the layer maps; the welded one keeps the
        // expo's full-screen blur rule off the strip.
        WlrLayershell.namespace: win.welded ? "ryoku-weld-expo" : "overview"
        WlrLayershell.layer: WlrLayer.Overlay
        // Only the focused monitor grabs the keyboard, so keys never double-fire.
        // A welded strip takes it on demand, so the bar's marks stay pressable on
        // Hyprland.
        WlrLayershell.keyboardFocus: !(shown && isFocused) ? WlrKeyboardFocus.None
            : win.welded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }

        // Hold the layer mapped through the outro, then unmap once it settles.
        Timer { id: closing; interval: Motion.window; repeat: false }
        onShownChanged: {
            if (shown) {
                if (isFocused)
                    kb.forceActiveFocus();
            } else {
                closing.restart();
            }
        }

        // Dim scrim over the (compositor-blurred) desktop; click-out dismisses.
        Rectangle {
            anchors.fill: parent
            color: win.welded ? "transparent" : Qt.rgba(0, 0, 0, 0.32)
            opacity: win.shown ? 1 : 0
            visible: opacity > 0.001
            Behavior on opacity { NumberAnimation { duration: Motion.window; easing.type: Motion.easeStandard } }
            MouseArea { anchors.fill: parent; onClicked: root.hide() }
        }

        C.WeldedCard {
            id: weld
            screen: root.screen
            surfaceId: "overview"
            open: win.shown
            hostVisible: win.visible
            cardWidth: body.width
            cardHeight: body.height
            onSeamLost: root.hide()
        }

        // A welded strip cycles on a wheel turn anywhere, like the expo.
        WheelHandler {
            enabled: win.welded && win.shown
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => {
                if (e.angleDelta.y !== 0)
                    body.cycle(e.angleDelta.y < 0 ? 1 : -1);
            }
        }

        Overview {
            id: body
            parent: win.welded ? weld.slot : win.contentItem
            x: 0
            y: 0
            width: win.welded ? implicitWidth : win.width
            height: win.welded ? implicitHeight : win.height
            compact: win.welded
            maxWidth: win.welded ? win.width - weld.place.margin * 2 : 0
            cellMax: Math.round((root.screen ? root.screen.height : 1080) * 0.11)
            previewsLive: win.shown || weld.moving
            s: win.s
            screenName: root.screen ? root.screen.name : ""
            active: win.shown
            // The resident models are warm, so data is ready without polling.
            dataReady: true
            focusHere: win.isFocused
            onRequestClose: root.hide()

            // reveal: fade + a small scale settle, like the launcher window. A
            // welded strip slides instead.
            opacity: win.welded || win.shown ? 1 : 0
            scale: win.welded || win.shown ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: Motion.window; easing.type: Motion.easeStandard } }
            Behavior on scale { NumberAnimation { duration: Motion.window; easing.type: Motion.easeExpo } }
        }

        // Keyboard: only the focused monitor's window handles keys.
        Item {
            id: kb
            anchors.fill: parent
            focus: win.shown && win.isFocused
            Keys.onPressed: (e) => {
                if (!win.isFocused)
                    return;
                var alt = (e.modifiers & Qt.AltModifier) !== 0;
                var shift = (e.modifiers & Qt.ShiftModifier) !== 0;
                if (e.key === Qt.Key_Escape) {
                    root.hide(); e.accepted = true;
                } else if (alt && (e.key === Qt.Key_Tab || e.key === Qt.Key_Right || e.key === Qt.Key_Backtab || e.key === Qt.Key_Left)) {
                    // Super+Alt+Tab: step across DESKTOPS (the top strip).
                    body.cycleDesktop((shift || e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) ? -1 : 1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right) {
                    body.cycle(shift ? -1 : 1); e.accepted = true;
                } else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) {
                    body.cycle(-1); e.accepted = true;
                } else if (e.key === Qt.Key_Down) {
                    body.cycle(1); e.accepted = true;
                } else if (e.key === Qt.Key_Up) {
                    body.cycle(-1); e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    body.activateSelected(); e.accepted = true;
                }
            }
        }
    }
}
