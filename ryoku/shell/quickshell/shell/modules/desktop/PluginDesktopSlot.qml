pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Ryoku.PluginKit.Singletons
import "Singletons"
import "../stage/Singletons" as StageCfg

// desktop placement frame for one plugin widget on the wallpaper layer.
// measures the plugin's natural size, pads it, draws an optional card/glass
// backing with a soft lift, and carries the same desktop control the shipped
// WidgetSlot (the clock) gives a built-in: left-drag to move (grid-snapped,
// clamped to the host), right-click for the menu, Ctrl+wheel or a bottom-right
// bracket to resize (scale 0.5..2.5), and a per-tile opacity. free position,
// scale, opacity and lock persist to plugins.json through the host.
//
// interaction is pointer-handler based, not a MouseArea grip: a DragHandler
// takes the grab only once the press travels past the drag threshold, so a
// click or double-click that never moves stays with the plugin's own control
// (a button, a style cycle, a slider) while a real drag moves the tile. A
// MouseArea grip cannot do this -- laid over the content it eats every click,
// laid under it never sees a press the plugin's own MouseArea already took.
Item {
    id: slot
    enabled: !slot.stageInputBlocked

    property string pluginId: ""
    property string monitor: ""              // output owning this tile
    property real freeX: 80
    property real freeY: 80
    property bool locked: false
    property real pad: 18
    property string bg: "card"            // none | card | glass
    property real radius: Theme.radius
    property real gridSize: 32
    property real scaleCfg: 1             // persisted scale, bound from the host
    property real opacityCfg: 1          // persisted opacity, bound from the host
    property real depthV: 0.5
    property bool spatial: false             // desktop's stageSpatial gate
    property real mouseNX: 0                 // shared smoothed cursor, -1..1
    property real mouseNY: 0
    // Keep the resize bracket present while an Edit widgets session is on: the
    // frame overlay above intercepts hover, so a hover-only bracket would never
    // reveal (see WidgetSlot).
    property bool composing: false
    property var stageController: null
    readonly property bool stageInputBlocked: !!(slot.stageController
        && slot.stageController.inputBlocked)
    readonly property real stageFramingDim: slot.stageController
        ? slot.stageController.framingDim : 0

    signal moved(real x, real y)
    signal resized(real scale)
    signal lockRequested(bool locked)
    signal menuRequested(real x, real y, string id)
    signal settingsRequested(string id)

    // build the plugin widget directly as a child of `holder` (via
    // createComponent, which renders Image correctly where Loader doesn't),
    // so the slot measures the widget's own implicit size exactly like
    // WidgetSlot hosts Clock directly. no wrapper Item between slot and widget.
    property string contentUrl: ""
    property var configure: null
    property var item: null
    property int _buildGeneration: 0
    onContentUrlChanged: _build()
    function _build() {
        const generation = ++slot._buildGeneration;
        if (!contentUrl || contentUrl.length === 0) {
            const previous = item;
            item = null;
            if (previous)
                previous.destroy();
            return;
        }
        const requestedUrl = contentUrl;
        const previous = item;
        const component = Qt.createComponent(requestedUrl);
        function publish() {
            if (generation !== slot._buildGeneration || requestedUrl !== slot.contentUrl)
                return;
            if (component.status === Component.Ready) {
                const next = component.createObject(holder);
                if (!next) {
                    console.warn("PluginDesktopSlot: could not create", requestedUrl);
                    return;
                }
                if (configure)
                    configure(next);
                item = next;
                if (previous && previous !== next)
                    previous.destroy();
            } else if (component.status === Component.Error) {
                console.warn("PluginDesktopSlot:", component.errorString());
            }
        }
        if (component.status === Component.Loading)
            component.statusChanged.connect(publish);
        else
            publish();
    }

    readonly property real cw: item ? item.implicitWidth : 100
    readonly property real ch: item ? item.implicitHeight : 100

    // drag/resize state. while holding (dragging/resizing, or briefly after
    // release until the persisted value lands) the rendered position/scale
    // stick to the live values so they never flash back to the old config
    // for a frame.
    property bool dragging: false
    property real dragX: 0
    property real dragY: 0
    property bool resizing: false
    property bool resizeMoved: false
    property string resizeCorner: "br"
    property real resizeOppX: 0
    property real resizeOppY: 0
    property real resizeStartWidth: 1
    property real resizeStartHeight: 1
    property real resizeStartScale: 1
    property real resizeStartDiag: 1
    readonly property bool holding: slot.dragging || slot.resizing || guard.running
    property bool stageMoveActive: false
    property real stageMoveGrabX: 0
    property real stageMoveGrabY: 0
    property real groupDragMinX: -Infinity
    property real groupDragMaxX: Infinity
    property real groupDragMinY: -Infinity
    property real groupDragMaxY: Infinity
    readonly property string stageMoveId: "plugin:" + slot.pluginId

    // live scale during a resize scrub. mirrors scaleCfg when idle; mutates
    // while resizing so the readout and content track the cursor without
    // writing to the host every frame (plugins have no setLive fast path).
    property real liveScale: 1
    onScaleCfgChanged: if (!slot.resizing) slot.liveScale = slot.scaleCfg
    Component.onCompleted: { slot.liveScale = slot.scaleCfg; _build(); }
    readonly property real effectiveScale: (slot.resizing || guard.running || scalePersist.running) ? slot.liveScale : slot.scaleCfg

    width: Math.max(1, slot.cw * slot.effectiveScale + slot.pad * 2)
    height: Math.max(1, slot.ch * slot.effectiveScale + slot.pad * 2)

    function clampX(v) { return Math.max(0, Math.min(v, (slot.parent ? slot.parent.width : v + slot.width) - slot.width)); }
    function clampY(v) { return Math.max(0, Math.min(v, (slot.parent ? slot.parent.height : v + slot.height) - slot.height)); }
    function snap(v) { return Math.round(v / slot.gridSize) * slot.gridSize; }
    function _quantiseScale(value, modifiers) {
        const bounded = Math.max(0.5, Math.min(2.5, value));
        if (Boolean(modifiers & Qt.ShiftModifier))
            return Math.round(bounded * 100) / 100;
        if (Math.abs(bounded - 1) < 0.03)
            return 1;
        return Math.round(bounded / 0.05) * 0.05;
    }
    function stageSetScale(value) {
        if (slot.locked)
            return;
        slot.liveScale = slot._quantiseScale(value, Qt.NoModifier);
        slot.resized(slot.liveScale);
        guard.restart();
    }
    function stageToggleLock() {
        slot.lockRequested(!slot.locked);
    }
    function stageBeginMove(point, modifiers) {
        if (slot.locked || slot.stageInputBlocked)
            return false;
        slot.stageMoveActive = true;
        slot.stageMoveGrabX = point.x - slot.x;
        slot.stageMoveGrabY = point.y - slot.y;
        slot.dragX = slot.x;
        slot.dragY = slot.y;
        if (slot.composing && slot.stageController) {
            const bounds = slot.stageController.widgetDragStarted(slot.stageMoveId);
            if (bounds.active === false) {
                slot.stageMoveActive = false;
                return false;
            }
            slot.groupDragMinX = bounds.minX;
            slot.groupDragMaxX = bounds.maxX;
            slot.groupDragMinY = bounds.minY;
            slot.groupDragMaxY = bounds.maxY;
        }
        return true;
    }
    function stageUpdateMove(point, modifiers) {
        if (!slot.stageMoveActive || slot.locked)
            return;
        const nx = point.x - slot.stageMoveGrabX;
        const ny = point.y - slot.stageMoveGrabY;
        if (!slot.dragging) {
            if (Math.abs(nx - slot.x) < 6 && Math.abs(ny - slot.y) < 6)
                return;
            slot.dragging = true;
        }
        slot.dragX = Math.max(slot.groupDragMinX,
            Math.min(slot.groupDragMaxX, slot.clampX(nx)));
        slot.dragY = Math.max(slot.groupDragMinY,
            Math.min(slot.groupDragMaxY, slot.clampY(ny)));
        if (slot.composing && slot.stageController) {
            const bounded = slot.stageController.widgetDragMoved(
                slot.stageMoveId, slot.dragX, slot.dragY, modifiers);
            slot.dragX = bounded.x;
            slot.dragY = bounded.y;
        }
    }
    function stageEndMove(modifiers) {
        if (!slot.stageMoveActive)
            return;
        if (slot.dragging) {
            const fx = Math.round(Math.max(slot.groupDragMinX,
                Math.min(slot.groupDragMaxX, slot.composing
                    ? slot.dragX : slot.snap(slot.dragX))));
            const fy = Math.round(Math.max(slot.groupDragMinY,
                Math.min(slot.groupDragMaxY, slot.composing
                    ? slot.dragY : slot.snap(slot.dragY))));
            const handled = slot.composing && slot.stageController
                && slot.stageController.widgetDragEnded(
                    slot.stageMoveId, fx, fy, modifiers);
            if (!handled)
                slot.moved(fx, fy);
            slot.dragging = false;
            guard.restart();
        } else if (slot.composing && slot.stageController) {
            slot.stageController.widgetDragCancelled(slot.stageMoveId);
        }
        slot.stageMoveActive = false;
        slot.groupDragMinX = -Infinity;
        slot.groupDragMaxX = Infinity;
        slot.groupDragMinY = -Infinity;
        slot.groupDragMaxY = Infinity;
    }
    function stageCancelMove() {
        if (!slot.stageMoveActive)
            return;
        if (slot.composing && slot.stageController)
            slot.stageController.widgetDragCancelled(slot.stageMoveId);
        slot.dragging = false;
        slot.stageMoveActive = false;
        slot.groupDragMinX = -Infinity;
        slot.groupDragMaxX = Infinity;
        slot.groupDragMinY = -Infinity;
        slot.groupDragMaxY = Infinity;
    }
    function stageBeginResize(corner, point, modifiers) {
        if (slot.locked || slot.stageInputBlocked)
            return;
        slot.resizeCorner = corner;
        slot.resizeStartScale = slot.effectiveScale;
        slot.resizeStartWidth = slot.width;
        slot.resizeStartHeight = slot.height;
        slot.resizeOppX = corner.indexOf("l") >= 0 ? slot.x + slot.width : slot.x;
        slot.resizeOppY = corner.indexOf("t") >= 0 ? slot.y + slot.height : slot.y;
        slot.resizeStartDiag = Math.max(1,
            Math.hypot(point.x - slot.resizeOppX, point.y - slot.resizeOppY));
        slot.dragX = slot.x;
        slot.dragY = slot.y;
        slot.resizeMoved = false;
        slot.resizing = true;
    }
    function stageUpdateResize(point, modifiers) {
        if (!slot.resizing)
            return;
        slot.resizeMoved = true;
        const distance = Math.max(1,
            Math.hypot(point.x - slot.resizeOppX, point.y - slot.resizeOppY));
        slot.liveScale = slot._quantiseScale(
            slot.resizeStartScale * distance / slot.resizeStartDiag, modifiers);
        const factor = slot.liveScale / Math.max(0.001, slot.resizeStartScale);
        const nextW = slot.resizeStartWidth * factor;
        const nextH = slot.resizeStartHeight * factor;
        slot.dragX = slot.resizeCorner.indexOf("l") >= 0
            ? slot.resizeOppX - nextW : slot.resizeOppX;
        slot.dragY = slot.resizeCorner.indexOf("t") >= 0
            ? slot.resizeOppY - nextH : slot.resizeOppY;
    }
    function stageEndResize() {
        if (!slot.resizing)
            return;
        if (!slot.resizeMoved) {
            slot.resizing = false;
            return;
        }
        slot.dragX = slot.clampX(slot.dragX);
        slot.dragY = slot.clampY(slot.dragY);
        slot.resized(slot.liveScale);
        slot.resizing = false;
        guard.restart();
    }
    function stageCancelResize() {
        slot.resizing = false;
        slot.liveScale = slot.scaleCfg;
    }
    function stageResetScale() {
        if (!slot.locked)
            slot.stageSetScale(1);
    }

    // A press that begins inside the plugin's own scroll area (a ListView or any
    // Flickable) has to scroll that list, not drag the tile: the DragHandler
    // declines the grab there (grabPermissions below) and steals everywhere else
    // -- bare chrome, or a full-surface gimmick MouseArea. Walk the content tree
    // once per press and test each Flickable's mapped bounds; mapToItem carries
    // the tiles' own scale transforms, where childAt does not.
    function _isFlickable(node) {
        return !!node && typeof node.contentX === "number" && typeof node.contentY === "number"
            && typeof node.flicking === "boolean";
    }
    function _walkScroll(node, x, y) {
        if (!node)
            return false;
        if (slot._isFlickable(node)) {
            const p = slot.mapToItem(node, x, y);
            if (p.x >= 0 && p.y >= 0 && p.x <= node.width && p.y <= node.height)
                return true;
        }
        const kids = node.children;
        if (kids)
            for (var i = 0; i < kids.length; i++)
                if (slot._walkScroll(kids[i], x, y))
                    return true;
        return false;
    }
    function _scrollableAt(x, y) { return slot.item ? slot._walkScroll(slot.item, x, y) : false; }

    x: slot.holding ? slot.dragX : slot.clampX(slot.freeX)
    y: slot.holding ? slot.dragY : slot.clampY(slot.freeY)
    Behavior on x { enabled: !slot.holding; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !slot.holding; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }


    // per-tile opacity (the menu and Ryoku Settings write desktopWidget.opacity),
    // clamped so a tile can fade back but never vanish or lose its clicks.
    opacity: Math.max(0.2, Math.min(1, slot.opacityCfg))
        * (1 - 0.75 * slot.stageFramingDim) * (slot._hovered ? 0.85 : 1)
    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    Timer { id: guard; interval: 90 }

    readonly property bool _sceneOn: slot.spatial && !slot.composing
    readonly property real _gainRaw: slot.spatial
            && StageCfg.Config.followMouse("spatial")
        ? StageCfg.Config.amountFactor("spatial")
            * StageCfg.Config.sensitivity("spatial")
            * StageCfg.Config.range("spatial") : 0
    property real _gain: slot._gainRaw
    Behavior on _gain { SmoothedAnimation { velocity: 2.5; duration: 200 } }
    readonly property real _pivot: StageCfg.StageBackend.pivotDistanceFor(slot.monitor)
    readonly property real _sceneH: slot.parent ? slot.parent.height : 0
    readonly property bool _hovered: slot._sceneOn && slotHover.hovered && !slot.holding
    property var _scene: slot._sceneOn
        ? StageCfg.StageBackend.widgetSceneAt(
            slot.depthV, slot._pivot, slot.mouseNX, slot.mouseNY, slot._gain,
            slot.x + slot.width / 2, slot.y + slot.height / 2,
            slot.width, slot.height, slot.parent.width, slot._sceneH)
        : null
    readonly property real _sceneDx: slot._scene ? slot._scene.dx : 0
    readonly property real _sceneDy: slot._scene ? slot._scene.dy : 0
    readonly property real _sceneScale: slot._scene ? slot._scene.scale : 1
    // Contact shadow: farther, wider and softer the nearer the tile rides; the
    // flat lift off the stage.
    readonly property real _nearness: Math.max(0, Math.min(1, slot.depthV))
    readonly property real _shadowAngle: StageCfg.Config.shadowAngle("spatial") * Math.PI / 180
    readonly property real _shadowSpan: slot._sceneOn ? 4 + 16 * slot._nearness : 6
    transform: [
        Scale {
            origin.x: slot.width / 2
            origin.y: slot.height / 2
            xScale: slot._sceneScale
            yScale: slot._sceneScale
        },
        Translate {
            x: slot._sceneDx
            y: slot._sceneDy
        }
    ]

    MultiEffect {
        source: backing
        anchors.fill: backing
        visible: !slot.resizing && slot.bg !== "none"
        shadowEnabled: true
        shadowColor: slot._sceneOn
            ? Qt.rgba(0, 0, 0, 0.30 + 0.40 * slot._nearness)
            : Qt.rgba(0, 0, 0, 0.5)
        shadowBlur: slot._sceneOn ? 0.80 + 0.20 * slot._nearness : 1.0
        shadowScale: slot._sceneOn ? 0.96 + 0.14 * slot._nearness : 1.0
        shadowHorizontalOffset: Math.round(slot._sceneOn
            ? Math.cos(slot._shadowAngle) * slot._shadowSpan : 0)
        shadowVerticalOffset: Math.round(slot._sceneOn
            ? Math.sin(slot._shadowAngle) * slot._shadowSpan : 6)
        blurMax: 32
        autoPaddingEnabled: true
    }

    Rectangle {
        id: backing
        anchors.fill: parent
        visible: slot.bg !== "none"
        radius: slot.radius
        // match the shipped desktop widgets (WidgetSlot): translucent dark
        // card with a faint white hairline, so plugin tiles read identical
        // to the clock on the wallpaper.
        color: slot.bg === "card" ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(16 / 255, 16 / 255, 24 / 255, 0.26)
        border.width: 1
        border.color: slot.bg === "card" ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.16)

        // glass sheen, matching WidgetSlot.
        Rectangle {
            visible: slot.bg === "glass"
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.06) }
            }
        }
    }

    // Outside compose mode the DragHandler shares the tile with plugin controls.
    // The compose frame calls the same move API after taking the topmost grab.
    DragHandler {
        id: dragger
        target: null
        enabled: !slot.composing && !slot.locked && !slot.stageInputBlocked
        acceptedButtons: Qt.LeftButton
        grabPermissions: slot._scrollableAt(
                dragger.centroid.pressPosition.x,
                dragger.centroid.pressPosition.y)
            ? PointerHandler.TakeOverForbidden
            : (PointerHandler.CanTakeOverFromItems
                | PointerHandler.CanTakeOverFromHandlersOfDifferentType
                | PointerHandler.ApprovesTakeOverByHandlersOfSameType
                | PointerHandler.ApprovesTakeOverByHandlersOfDifferentType
                | PointerHandler.ApprovesTakeOverByItems
                | PointerHandler.ApprovesCancellation)
        onActiveChanged: {
            if (dragger.active) {
                const pressPoint = slot.mapToItem(slot.parent,
                    dragger.centroid.pressPosition.x,
                    dragger.centroid.pressPosition.y);
                slot.stageBeginMove(pressPoint, Qt.NoModifier);
                const currentPoint = slot.mapToItem(slot.parent,
                    dragger.centroid.position.x,
                    dragger.centroid.position.y);
                slot.stageUpdateMove(currentPoint, Qt.NoModifier);
            } else {
                slot.stageEndMove(Qt.NoModifier);
            }
        }
        onCentroidChanged: {
            const point = slot.mapToItem(slot.parent,
                dragger.centroid.position.x, dragger.centroid.position.y);
            slot.stageUpdateMove(point, Qt.NoModifier);
        }
    }

    // right-click opens the tile menu. a separate handler because DragHandler is
    // left-only; the plugin's own controls take LeftButton, so a right press
    // always reaches here, over content or bare chrome alike.
    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        enabled: !slot.composing && !slot.stageInputBlocked
        onTapped: eventPoint => {
            const position = slot.mapToItem(slot.parent,
                eventPoint.position.x, eventPoint.position.y);
            slot.menuRequested(position.x, position.y, slot.pluginId);
        }
    }

    // content holder: a Scale transform applies the live scale, so the
    // plugin grows visibly from its top-left as the resize bracket scrubs.
    // slot width/height grow in lockstep so the backing tracks the content.
    Item {
        id: holder
        x: slot.pad
        y: slot.pad
        width: slot.cw
        height: slot.ch
        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: slot.effectiveScale
            yScale: slot.effectiveScale
        }
    }

    // hover state for the slot and its children, so the resize handle stays
    // lit while you reach across to it.
    HoverHandler {
        id: slotHover
        cursorShape: slot.locked ? Qt.ArrowCursor : (slot.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

        onPointChanged: {
            if (!slot._sceneOn)
                return;
            const w = slot.parent ? slot.parent.width : 0;
            const h = slot.parent ? slot.parent.height : 0;
            if (w <= 0 || h <= 0)
                return;
            StageCfg.StageBackend.setCursor(slot.monitor,
                point.scenePosition.x / w * 2 - 1,
                point.scenePosition.y / h * 2 - 1);
        }
    }

    // scroll to scale: Ctrl + wheel anywhere on the tile resizes it, an easier
    // reach than the corner bracket. liveScale keeps the scrub smooth; the
    // settle timer does the one persisting write, through resized(), once
    // scrolling stops (plugins have no per-frame setLive fast path).
    WheelHandler {
        enabled: !slot.locked && !slot.stageInputBlocked
        acceptedModifiers: Qt.ControlModifier
        onWheel: (event) => {
            const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
            slot.liveScale = slot._quantiseScale(slot.effectiveScale + step,
                event.modifiers);
            slot.dragX = slot.x;
            slot.dragY = slot.y;
            scalePersist.restart();
        }
    }
    Timer {
        id: scalePersist
        interval: 350
        onTriggered: { slot.resized(slot.liveScale); guard.restart(); }
    }

    // Outside the editor the bottom-right grip remains available. StageOutline
    // supplies all four corners while the editor is composing.
    Item {
        id: handle
        width: 22
        height: 22
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        opacity: (((slotHover.hovered && !slot.composing) && !slot.locked
            && !slot.dragging) || (slot.resizing && !slot.composing)) ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 13
            height: 2
            radius: Theme.radius
            color: (hgrip.containsMouse || slot.resizing) ? Theme.accent : Theme.faint
        }
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 2
            height: 13
            radius: Theme.radius
            color: (hgrip.containsMouse || slot.resizing) ? Theme.accent : Theme.faint
        }

        MouseArea {
            id: hgrip
            anchors.fill: parent
            enabled: !slot.locked && !slot.stageInputBlocked
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            onPressed: mouse => {
                const p = hgrip.mapToItem(slot.parent, mouse.x, mouse.y);
                slot.stageBeginResize("br", p, mouse.modifiers);
            }
            onPositionChanged: mouse => {
                const p = hgrip.mapToItem(slot.parent, mouse.x, mouse.y);
                slot.stageUpdateResize(p, mouse.modifiers);
            }
            onReleased: slot.stageEndResize()
            onCanceled: slot.stageCancelResize()
            onDoubleClicked: slot.stageResetScale()
        }
    }

    // live size readout while resizing.
    Rectangle {
        visible: !slot.composing && (slot.resizing || scalePersist.running)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 26
        anchors.bottomMargin: 26
        width: roText.implicitWidth + 16
        height: 20
        radius: Theme.radius
        color: Qt.rgba(0, 0, 0, 0.62)
        Text {
            id: roText
            anchors.centerIn: parent
            text: Math.round(slot.effectiveScale * 100) + "%"
            color: Theme.cream
            font.family: Theme.mono
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }
}
