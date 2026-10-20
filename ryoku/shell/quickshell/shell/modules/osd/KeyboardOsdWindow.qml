import QtQuick
import Quickshell
import Quickshell.Wayland
import shell.services
import Ryoku.Ui.Singletons
import "../../components"

PanelWindow {
    id: win

    required property var modelData

    readonly property real osdScale: 0.9

    readonly property real us: Tokens.uiScaleFor(
        modelData ? modelData.name : ""
    )

    readonly property real pad: 20 * us
    readonly property real slide: 14 * us

    property bool showing: false
    property real prog: showing ? 1 : 0

    Behavior on prog {
        NumberAnimation {
            duration: Motion.effects
            easing.type: Easing.OutCubic
        }
    }

    screen: modelData

    visible: prog > 0.01 || showing

    color: "transparent"

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ryoku-keyboard-osd"

    // Under a bar style's seam the welded panels hang where this would sit, over
    // their search rows, so it shows at the bottom instead, one volume OSD
    // above that one's place.
    readonly property bool belowPanels: !!SidebarState.seamFor(modelData)

    anchors.top: !win.belowPanels
    anchors.bottom: win.belowPanels
    anchors.left: true
    anchors.right: true

    margins.top: win.belowPanels ? 0 : 24 * us
    margins.bottom: win.belowPanels ? 120 * us : 0

    implicitHeight: box.height + slide

    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        width: content.implicitWidth + pad * 2
        height: content.implicitHeight + pad - 4

        radius: Theme.radiusWindow

        color: Theme.surface
        border.width: Theme.borderWidth
        border.color: Theme.outline

        opacity: Theme.windowOpacity * win.prog

        antialiasing: true

        transformOrigin: Item.Bottom

        transform: [
            Translate {
                y: -win.prog * win.slide
            },
            Scale {
                origin.x: box.width / 2
                origin.y: box.height
                xScale: win.osdScale
                yScale: win.osdScale
            }
        ]

        KeyboardOsd {
            id: content

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right

            anchors.leftMargin: win.pad
            anchors.rightMargin: win.pad

            us: win.us
        }
    }

    mask: Region {}

    Timer {
        id: hideTimer

        interval: Motion.osdHide

        onTriggered: {
            win.showing = false
        }
    }

    Connections {
        target: KeyboardLayout

        function onVariantChanged() {
            win.showing = true
            hideTimer.restart()
        }
    }
}
