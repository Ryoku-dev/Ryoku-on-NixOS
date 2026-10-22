pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import shell.services
import Ryoku.Ui.Singletons

// The keyboard layout readout is a passive top-centre overlay on every output.
// Its shipped panel fades and slides without taking focus, and eased progress
// keeps the window mapped until that exit has finished.
PanelWindow {
    id: win

    required property var modelData

    // These scale terms preserve the shipped panel's compact size while
    // following each output's UI scale.
    readonly property real osdScale: 0.9
    readonly property real us: Tokens.uiScaleFor(modelData ? modelData.name : "")
    readonly property real pad: 20 * win.us
    readonly property real slide: 14 * win.us
    // Installed designs share the source and window policy but choose their
    // own implicit size and placement.
    readonly property bool storeRuns: designLoader.storeRuns
    readonly property bool stockRuns: Designs.osdReady && !win.storeRuns

    property real prog: feed.flashing ? 1 : 0
    Behavior on prog {
        NumberAnimation {
            duration: Motion.effects
            easing.type: Easing.OutCubic
        }
    }

    // A design's reveal owns its exit lifetime; the shipped panel uses prog.
    screen: modelData
    visible: Designs.osdReady
        && (feed.flashing || (win.storeRuns ? designLoader.reveal : win.prog) > 0.01)
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ryoku-keyboard-osd"

    // Under a bar style's seam the welded panels hang where this would sit, over
    // their search rows, so the shipped panel shows at the bottom instead, one
    // volume OSD above that one's place.
    readonly property bool belowPanels: !win.storeRuns && !!SidebarState.seamFor(modelData)

    // A single selected edge centres the other axis. No edge anchors centre
    // the whole surface, while the shipped panel keeps its top span.
    anchors.top: win.storeRuns ? designLoader.placement === "top" : !win.belowPanels
    anchors.bottom: win.storeRuns ? designLoader.placement === "bottom" : win.belowPanels
    anchors.left: !win.storeRuns || designLoader.placement === "left"
    anchors.right: !win.storeRuns || designLoader.placement === "right"
    margins.top: win.storeRuns ? (designLoader.placement === "top" ? 24 * win.us : 0)
        : (win.belowPanels ? 0 : 24 * win.us)
    margins.bottom: win.storeRuns ? (designLoader.placement === "bottom" ? 24 * win.us : 0)
        : (win.belowPanels ? 120 * win.us : 0)
    margins.left: win.storeRuns && designLoader.placement === "left" ? 24 * win.us : 0
    margins.right: win.storeRuns && designLoader.placement === "right" ? 24 * win.us : 0

    implicitWidth: win.storeRuns && designLoader.item
        ? designLoader.item.implicitWidth : 0
    implicitHeight: win.storeRuns && designLoader.item
        ? designLoader.item.implicitHeight : box.height + win.slide

    OsdSource {
        id: feed
        kind: "keyboard"
    }

    Rectangle {
        id: box
        visible: win.stockRuns
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: content.implicitWidth + win.pad * 2
        height: content.implicitHeight + win.pad - 4
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
            layout: feed.label
        }
    }

    OsdDesignLoader {
        id: designLoader
        anchors.fill: parent
        kind: "keyboard"
        screen: win.modelData
        us: win.us
        shown: feed.flashing
        value: feed.value
        maxValue: feed.maxValue
        muted: feed.muted
        icon: feed.iconName
        iconSource: Qt.resolvedUrl("../../components/icons/input-keyboard-symbolic.svg")
        label: feed.label
    }

    // The layout readout must not intercept desktop input.
    mask: Region {}
}
