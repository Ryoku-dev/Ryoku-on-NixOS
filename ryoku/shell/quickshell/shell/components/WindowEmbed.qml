pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons

// Neutral window embed. Where the compositor can pin a window to a layer
// surface's screen and corner (caps.windowEmbed), the provider bridge places
// the window under this frame's cut-out; where it cannot, embed() and park()
// are inert and the caller shows a plain window instead (see `available`).
//
// The caller owns the geometry: it hands the rectangle, the layer namespace the
// window must sit under, and the title that identifies the window. The bridge
// owns the compositor-specific way of doing it.
Item {
    id: root

    property string title: ""
    property string layerNamespace: ""
    property real x0: 0
    property real y0: 0
    property real width0: 0
    property real height0: 0
    property int cornerRadius: 0
    property int parkCoordinate: 99000

    /// The layout moved under the embedded window; re-place by calling embed().
    signal layoutChanged()

    readonly property bool available: Wm.caps.windowEmbed === true

    property QtObject _bridge: null
    property var _component: null

    readonly property bool _canBridge: Wm.caps.windowEmbed === true
    on_CanBridgeChanged: root._build()
    Component.onCompleted: root._build()

    function _build() {
        if (root._bridge || !Wm.caps.windowEmbed)
            return;
        if (!root._component)
            root._component = Qt.createComponent("Ryoku.Wm.Hyprland", "WindowEmbedBridge");
        const c = root._component;
        if (c.status === Component.Loading) {
            c.statusChanged.connect(root._build);
            return;
        }
        if (c.status !== Component.Ready)
            return;
        const b = c.createObject(root);
        if (!b)
            return;
        b.layoutChanged.connect(root.layoutChanged);
        root._bridge = b;
    }

    function embed(): void {
        if (!root._bridge)
            return;
        root._bridge.embed(root.title, root.layerNamespace, root.x0, root.y0,
            root.width0, root.height0, root.cornerRadius);
    }

    function park(): void {
        if (!root._bridge)
            return;
        root._bridge.park(root.title, root.parkCoordinate);
    }
}
