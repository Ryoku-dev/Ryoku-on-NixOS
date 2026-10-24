pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons

// Neutral workspace-slide reading. Where the compositor reports how it slides
// between workspaces (caps.workspaceSlideStyle), the provider bridge parses its
// animation table and these properties carry the real numbers; where it cannot,
// they keep the built-in defaults and the consumer animates to its own curve
// (see `available`).
//
// Read on demand: call refresh() the first time the value is needed rather than
// at shell start, so a feature most sessions never open never spawns a probe.
Item {
    id: root

    /// False when the compositor animates workspaces instantly.
    readonly property bool slides: root._bridge ? root._bridge.slides : true
    /// "x", "y" or "none": which way the sheets go.
    readonly property string axis: root._bridge ? root._bridge.axis : "x"
    /// The slide distance as a fraction of the screen; 1 for a plain slide.
    readonly property real distance: root._bridge ? root._bridge.distance : 1
    /// Whether the sheets crossfade as they go.
    readonly property bool fade: root._bridge ? root._bridge.fade : false
    /// The animation's duration in milliseconds.
    readonly property int durationMs: root._bridge ? root._bridge.durationMs : 500
    /// Six bezier values for Easing.BezierSpline.
    readonly property var curve: root._bridge ? root._bridge.curve
        : [0.25, 0.1, 0.25, 1, 1, 1]

    /// The reading changed (a config reload re-reads on its own).
    signal refreshed()

    readonly property bool available: Wm.caps.workspaceSlideStyle === true

    property QtObject _bridge: null
    property var _component: null

    readonly property bool _canBridge: Wm.caps.workspaceSlideStyle === true
    on_CanBridgeChanged: root._build()
    Component.onCompleted: root._build()

    // A refresh asked for before the bridge finished loading must not be
    // dropped: the caller only asks once, on the first open.
    property bool _pending: false

    function _build() {
        if (root._bridge || !Wm.caps.workspaceSlideStyle)
            return;
        if (!root._component)
            root._component = Qt.createComponent("Ryoku.Wm.Hyprland", "WorkspaceSlideBridge");
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
        b.refreshed.connect(root.refreshed);
        root._bridge = b;
        if (root._pending) {
            root._pending = false;
            b.refresh();
        }
    }

    function refresh(): void {
        if (root._bridge)
            root._bridge.refresh();
        else
            root._pending = true;
    }
}
