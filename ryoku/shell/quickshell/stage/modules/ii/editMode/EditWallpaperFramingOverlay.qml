import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import stage
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.common.functions
import Ryoku.Ui as RyokuUi
import Ryoku.Ui.Singletons

/**
 * Edit Mode's wallpaper, moved by hand: the overlay the desktop card turns into
 * while the Wallpaper catalogue is open on the Desktop tab.
 *
 * Drawn on the widgets surface (BackgroundWidgetsWindow), in the desktop's own
 * coordinates, because that is the surface that takes the pointer over the
 * card; the picture it moves is on the wallpaper surface below. The two meet
 * in WallpaperLayout's live values: a drag writes them, the wallpaper surface
 * draws from them, and the release is the one config write (and history
 * entry) the gesture makes.
 *
 * Gestures: drag to move, wheel or pinch to zoom about the pointer, double
 * click to start over. Everything else - turn, mirror, centre, the exact zoom -
 * is a button on the dock at the bottom of the card and on the panel.
 *
 * Things it shows so nothing happens behind the user's back:
 *   - the thirds while dragging, and the centre lines when the picture snaps
 *     to them;
 *   - a glow on any edge the picture is pressed against (there is no further
 *     to go that way - the picture always covers the screen);
 *   - a coach line naming the gestures, which turns into the reason when a
 *     gesture did nothing (no room to move at 100%, the zoom's floor and why
 *     it is there) and says "Centred" while a drag holds the centre.
 *
 * Nothing here is scaled by the card: the dock, the coach line and the guides
 * undo the card's shrink (`counterScale`) and draw at 1:1. The guides are also
 * clipped to the card's rounded corner (`cardRadius`, in screen pixels).
 */
Item {
    id: root

    required property string screenName
    // The surface's net content scale (the mode's shrink): undone by the
    // controls so they draw at native size on the card.
    property real contentScale: 1
    readonly property real counterScale: 1 / Math.max(0.05, root.contentScale)
    // The card's corner on screen (EditModeCard's), for the guides' clip.
    property real cardRadius: 0
    // Whether the host is showing the overlay (false while it fades out).
    property bool shown: true

    // ── Entrance ─────────────────────────────────────────────────────────────
    // The coach line and the dock arrive as the page pattern does - a fade and
    // a 24px rise - the coach first and the dock a beat behind it; leaving,
    // they sink back together on the exit curve.
    property real coachIn: 0
    property real dockIn: 0
    readonly property var entranceMotion: root.shown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit
    function syncEntrance() {
        if (root.shown) {
            root.coachIn = 1;
            if (Appearance.reducedMotion)
                root.dockIn = 1;
            else
                dockStagger.restart();
        } else {
            dockStagger.stop();
            root.coachIn = 0;
            root.dockIn = 0;
        }
    }
    onShownChanged: root.syncEntrance()
    Component.onCompleted: root.syncEntrance()
    Timer {
        id: dockStagger
        interval: 70
        onTriggered: root.dockIn = 1
    }
    Behavior on coachIn {
        enabled: !Appearance.reducedMotion
        NumberAnimation {
            duration: root.entranceMotion.duration
            easing.type: root.entranceMotion.type
            easing.bezierCurve: root.entranceMotion.bezierCurve
        }
    }
    Behavior on dockIn {
        enabled: !Appearance.reducedMotion
        NumberAnimation {
            duration: root.entranceMotion.duration
            easing.type: root.entranceMotion.type
            easing.bezierCurve: root.entranceMotion.bezierCurve
        }
    }

    readonly property string sourcePath: WallpaperLayout.livePath
    readonly property var geometry: WallpaperLayout.geometryFor(root.screenName)
    readonly property bool ready: root.geometry !== null
    readonly property var frame: root.ready
        ? WallpaperFraming.layout(root.geometry.planeWidth, root.geometry.planeHeight,
            root.geometry.imageWidth, root.geometry.imageHeight,
            WallpaperLayout.liveFraming, WallpaperLayout.liveAngle)
        : null
    readonly property var target: WallpaperLayout.gestureTarget()
    readonly property bool canMoveX: root.frame !== null && root.frame.rangeX > 0.5
    readonly property bool canMoveY: root.frame !== null && root.frame.rangeY > 0.5
    readonly property bool canMove: root.canMoveX || root.canMoveY
    readonly property bool identity: WallpaperFraming.isIdentity(WallpaperLayout.liveFraming)

    // ── Gesture state ────────────────────────────────────────────────────────
    property bool dragging: false
    property var dragStart: null
    property real pressX: 0
    property real pressY: 0
    // A drag on a picture with no room to move, already explained once.
    property bool moveRefused: false
    property bool snappedX: false
    property bool snappedY: false
    // Which guide a snapped axis sits on: 0 the first third, 1 the centre,
    // 2 the second third; -1 none.
    property int snapIndexX: -1
    property int snapIndexY: -1
    readonly property bool onThird: root.snapIndexX === 0 || root.snapIndexX === 2
        || root.snapIndexY === 0 || root.snapIndexY === 2

    // The point the snap carries: the picture's face or main detail when
    // WallpaperLayout has found one, else its centre.
    readonly property var pointOfInterest: WallpaperLayout.pointOfInterestFor(root.sourcePath)
    readonly property bool tracksFace: root.pointOfInterest !== null && root.pointOfInterest.kind === "face"
    readonly property point interestOffset: {
        if (root.frame === null || root.pointOfInterest === null)
            return Qt.point(0, 0);
        const p = WallpaperFraming.pointOffset(root.frame, root.pointOfInterest.x, root.pointOfInterest.y);
        return Qt.point(p.x, p.y);
    }
    // The guides, from the screen's centre: a third, the centre, a third.
    readonly property var guideFractions: [1 / 3, 1 / 2, 2 / 3]
    function snapTargets() {
        const p = root.interestOffset;
        return {
            "x": root.guideFractions.map(f => (f - 0.5) * root.width - p.x),
            "y": root.guideFractions.map(f => (f - 0.5) * root.height - p.y)
        };
    }
    property bool atLeft: false
    property bool atRight: false
    property bool atTop: false
    property bool atBottom: false

    // A pointer from the plane's centre: the card is the screen, and in the
    // mode the plane sits centred on it (the parallax is held at the centre).
    function fromCentre(x, y) {
        return Qt.point(x - root.width / 2, y - root.height / 2);
    }

    function clearWalls() {
        root.atLeft = false;
        root.atRight = false;
        root.atTop = false;
        root.atBottom = false;
        root.snappedX = false;
        root.snappedY = false;
        root.snapIndexX = -1;
        root.snapIndexY = -1;
    }

    // The line under the strip, for a gesture that could not do what it was
    // asked. Shown for a moment, then the usual hint comes back.
    property string notice: ""
    function say(text) {
        root.notice = text;
        noticeTimer.restart();
    }
    Timer {
        id: noticeTimer
        interval: 2200
        onTriggered: root.notice = ""
    }

    function zoomBy(factor, px, py) {
        if (!root.ready)
            return;
        const base = WallpaperLayout.gestureTarget();
        const wanted = base.zoom * factor;
        if (wanted < WallpaperFraming.zoomMin - 0.0001 && base.zoom <= WallpaperFraming.zoomMin + 0.0001) {
            root.say(Translation.tr("100% is the smallest zoom: the lock screen zooms out to it"));
            return;
        }
        if (wanted > WallpaperFraming.zoomMax + 0.0001 && base.zoom >= WallpaperFraming.zoomMax - 0.0001) {
            root.say(Translation.tr("That is as far as it zooms"));
            return;
        }
        const g = root.geometry;
        const next = WallpaperFraming.zoomAt(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight, base, wanted, px, py);
        WallpaperLayout.stepGesture(next);
    }

    // A scroll's pan, in plane pixels the way a drag counts them.
    function panBy(dx, dy) {
        if (!root.ready)
            return;
        const g = root.geometry;
        const base = WallpaperLayout.gestureTarget();
        const at = WallpaperFraming.layout(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight, base);
        if (at.rangeX <= 0.5 && at.rangeY <= 0.5) {
            root.say(Translation.tr("Zoom in first to make room to move it"));
            return;
        }
        const result = WallpaperFraming.panTo(base, dx, dy, at.rangeX, at.rangeY, 0);
        WallpaperLayout.nudgeGesture(Object.assign({}, base, { "x": result.x, "y": result.y }));
    }

    // The wallpaper surface publishes the geometry once its size probe
    // answers, which takes three seconds at worst. Past that, something is
    // wrong with the picture, and the coach line says so instead of
    // measuring forever.
    property bool measureFailed: false
    onReadyChanged: if (root.ready) root.measureFailed = false
    Timer {
        interval: 5000
        running: !root.ready && !root.measureFailed
        onTriggered: root.measureFailed = true
    }

    function zoomTo(zoom) {
        if (!root.ready)
            return;
        const g = root.geometry;
        WallpaperLayout.stepGesture(WallpaperFraming.zoomAt(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight,
            WallpaperLayout.gestureTarget(), zoom, 0, 0));
    }

    // The card's widgets are still there, dimmed; the pointer belongs to the
    // picture for as long as this is up.
    MouseArea {
        id: gestureArea
        anchors.fill: parent
        enabled: root.ready
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: mouse => {
            WallpaperLayout.beginGesture();
            root.dragStart = WallpaperFraming.normalize(WallpaperLayout.liveFraming);
            root.pressX = mouse.x;
            root.pressY = mouse.y;
            root.clearWalls();
            root.moveRefused = false;
            root.dragging = true;
        }
        onPositionChanged: mouse => {
            if (!root.dragging || root.frame === null)
                return;
            // Said once the hand actually moves: a click or a double click
            // is not an attempt to drag.
            if (!root.canMove) {
                if (!root.moveRefused && Math.hypot(mouse.x - root.pressX, mouse.y - root.pressY) > 6) {
                    root.moveRefused = true;
                    root.say(Translation.tr("Zoom in first to make room to move it"));
                }
                return;
            }
            // The snap is a few pixels ON THE CARD, whatever the shrink; it
            // carries the point of interest onto the centre or a third.
            const result = WallpaperFraming.panTo(root.dragStart, mouse.x - root.pressX, mouse.y - root.pressY,
                root.frame.rangeX, root.frame.rangeY, 8 * root.counterScale, root.snapTargets());
            root.snappedX = result.snappedX;
            root.snappedY = result.snappedY;
            root.snapIndexX = result.snapIndexX;
            root.snapIndexY = result.snapIndexY;
            root.atLeft = result.atLeft;
            root.atRight = result.atRight;
            root.atTop = result.atTop;
            root.atBottom = result.atBottom;
            WallpaperLayout.updateGesture(Object.assign({}, root.dragStart, { "x": result.x, "y": result.y }));
        }
        onReleased: root.finishDrag()
        onCanceled: root.finishDrag()
        onDoubleClicked: {
            if (root.identity)
                return;
            WallpaperLayout.resetFraming(root.screenName);
            root.say(Translation.tr("Back to the full picture"));
        }
        // A mouse wheel's notch zooms; a touchpad's two-finger scroll moves
        // the picture with the fingers, and zooms with Ctrl held (pinch is
        // the other way). Told apart by ScrollWheel's rule: a notch is a full
        // angle step, a touchpad's deltas are small and continuous. A tilted
        // wheel, or Shift, moves across.
        onWheel: wheel => {
            const scrolling = Config.options?.interactions?.scrolling;
            const threshold = scrolling?.mouseScrollDeltaThreshold ?? 120;
            const ax = wheel.angleDelta.x;
            const ay = wheel.angleDelta.y;
            const notch = Math.abs(ax) >= threshold || Math.abs(ay) >= threshold;
            const ctrl = (wheel.modifiers & Qt.ControlModifier) !== 0;
            const shift = (wheel.modifiers & Qt.ShiftModifier) !== 0;
            if (ctrl || (notch && ay !== 0 && !shift)) {
                const delta = ay !== 0 ? ay : ax;
                if (delta === 0)
                    return;
                const p = root.fromCentre(wheel.x, wheel.y);
                root.zoomBy(Math.pow(1.0012, delta), p.x, p.y);
                return;
            }
            if (notch) {
                root.panBy(ScrollWheel.step(ax !== 0 ? ax : ay, 0, scrolling), 0);
                return;
            }
            const dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : ax / 8;
            const dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : ay / 8;
            if (dx !== 0 || dy !== 0)
                root.panBy(dx, dy);
        }
    }

    function finishDrag() {
        if (!root.dragging)
            return;
        root.dragging = false;
        root.clearWalls();
        WallpaperLayout.endGesture();
    }

    // Touchpad and touchscreen pinches, about where the fingers are.
    PinchHandler {
        id: pinch
        target: null
        enabled: root.ready
        property var startFraming: null
        property point startCentre: Qt.point(0, 0)
        // The zoom's floor or ceiling, explained once per pinch.
        property bool limitSaid: false

        onActiveChanged: {
            if (pinch.active) {
                pinch.limitSaid = false;
                WallpaperLayout.beginGesture();
                pinch.startFraming = WallpaperFraming.normalize(WallpaperLayout.liveFraming);
                pinch.startCentre = root.fromCentre(pinch.centroid.position.x, pinch.centroid.position.y);
                return;
            }
            WallpaperLayout.endGesture();
        }
        onActiveScaleChanged: {
            if (!pinch.active || pinch.startFraming === null || !root.ready)
                return;
            const wanted = pinch.startFraming.zoom * pinch.activeScale;
            if (!pinch.limitSaid && wanted < WallpaperFraming.zoomMin - 0.0001) {
                pinch.limitSaid = true;
                root.say(Translation.tr("100% is the smallest zoom: the lock screen zooms out to it"));
            } else if (!pinch.limitSaid && wanted > WallpaperFraming.zoomMax + 0.0001) {
                pinch.limitSaid = true;
                root.say(Translation.tr("That is as far as it zooms"));
            }
            const g = root.geometry;
            const next = WallpaperFraming.zoomAt(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight,
                pinch.startFraming, wanted, pinch.startCentre.x, pinch.startCentre.y);
            WallpaperLayout.updateGesture(next);
        }
    }

    // ── Guides ───────────────────────────────────────────────────────────────
    // Everything drawn over the picture lives inside the card's own corner:
    // the card is a rounded rectangle on screen, and a square guide or glow
    // laid over it leaked past the curve as a sliver of light in each corner.
    ClippingRectangle {
        id: guides
        anchors.fill: parent
        color: "transparent"
        radius: root.cardRadius * root.counterScale

        // Thirds while the picture is being moved: where a composition is
        // usually read from, which is the question a drag is answering.
        Item {
            anchors.fill: parent
            opacity: root.dragging ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Repeater {
                model: [1 / 3, 2 / 3]
                delegate: Item {
                    id: thirds
                    required property real modelData
                    anchors.fill: parent

                    Rectangle {
                        x: parent.width * thirds.modelData - width / 2
                        width: root.counterScale
                        height: parent.height
                        color: Appearance.colors.colOnSurface
                        opacity: 0.35
                    }
                    Rectangle {
                        y: parent.height * thirds.modelData - height / 2
                        width: parent.width
                        height: root.counterScale
                        color: Appearance.colors.colOnSurface
                        opacity: 0.35
                    }
                }
            }
        }

        // The guide a drag snapped to, lit: the centre or a third, per axis.
        Repeater {
            model: root.guideFractions
            delegate: Rectangle {
                required property real modelData
                required property int index
                x: parent.width * modelData - width / 2
                width: 2 * root.counterScale
                height: parent.height
                color: Appearance.colors.colPrimary
                opacity: root.dragging && root.snapIndexX === index ? 0.9 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
        Repeater {
            model: root.guideFractions
            delegate: Rectangle {
                required property real modelData
                required property int index
                y: parent.height * modelData - height / 2
                width: parent.width
                height: 2 * root.counterScale
                color: Appearance.colors.colPrimary
                opacity: root.dragging && root.snapIndexY === index ? 0.9 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        // The point the snap carries, while dragging: it morphs from a plain
        // circle into a burst when it lands on a guide.
        MaterialShapeWrappedMaterialSymbol {
            readonly property bool snapped: root.snappedX || root.snappedY
            visible: opacity > 0
            opacity: root.dragging && root.pointOfInterest !== null && root.frame !== null ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            x: root.frame !== null ? root.width / 2 + root.frame.x + root.interestOffset.x - width / 2 : 0
            y: root.frame !== null ? root.height / 2 + root.frame.y + root.interestOffset.y - height / 2 : 0
            scale: root.counterScale
            text: root.tracksFace ? "face" : "center_focus_weak"
            iconSize: 18
            padding: 8
            fill: snapped ? 1 : 0
            shape: snapped ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Circle
            color: snapped ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
            colSymbol: snapped ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // The walls: a soft glow fading in from an edge the picture is pressed
        // against. A gradient, not an outline.
        EdgeGlow {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: depth
            lit: root.dragging && root.atLeft
        }
        EdgeGlow {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: depth
            reversed: true
            lit: root.dragging && root.atRight
        }
        EdgeGlow {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: depth
            vertical: true
            lit: root.dragging && root.atTop
        }
        EdgeGlow {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: depth
            vertical: true
            reversed: true
            lit: root.dragging && root.atBottom
        }
    }

    component EdgeGlow: Rectangle {
        id: glow
        property bool lit: false
        property bool vertical: false
        property bool reversed: false
        readonly property real depth: 48 * root.counterScale
        opacity: glow.lit ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        gradient: Gradient {
            orientation: glow.vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop {
                position: 0
                color: glow.reversed ? "transparent" : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
            }
            GradientStop {
                position: 1
                color: glow.reversed ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) : "transparent"
            }
        }
    }

    // ── The coach line and the dock ──────────────────────────────────────────
    readonly property real controlHeight: Tokens.ctlH + Tokens.s3
    readonly property bool hasNotice: root.notice !== ""
    readonly property bool showsSnap: root.dragging && (root.snappedX || root.snappedY) && !root.hasNotice
    readonly property string coachText: {
        if (root.hasNotice)
            return root.notice;
        if (root.showsSnap) {
            if (root.tracksFace)
                return root.onThird ? Translation.tr("Face on a third") : Translation.tr("Face centred");
            return root.onThird ? Translation.tr("On a third") : Translation.tr("Centred");
        }
        if (!root.ready)
            return root.measureFailed ? Translation.tr("Couldn't measure this picture")
                : Translation.tr("Measuring the wallpaper…");
        return Translation.tr("Drag to move · Wheel or pinch to zoom · Double-click to reset");
    }

    ColumnLayout {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.s5 * root.counterScale
        spacing: Tokens.s2
        scale: root.counterScale
        transformOrigin: Item.Bottom

        Rectangle {
            id: coach
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width - Tokens.s5 * 2
            implicitWidth: Math.min(coachRow.implicitWidth + Tokens.s4 * 2,
                root.width - Tokens.s5 * 2)
            implicitHeight: Tokens.ctlH + Tokens.s2
            radius: Tokens.radius
            color: Tokens.paper
            border.width: Tokens.border
            border.color: root.hasNotice ? Tokens.lineStrong : Tokens.line
            opacity: root.coachIn * (dockHover.hovered
                || (root.dragging && !root.showsSnap && !root.hasNotice) ? 0 : 1)
            visible: opacity > 0
            transform: Translate { y: (1 - root.coachIn) * Tokens.s5 }

            Behavior on opacity {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.snap }
            }
            Behavior on border.color {
                enabled: !Tokens.reduceMotion
                ColorAnimation { duration: Tokens.snap }
            }

            RowLayout {
                id: coachRow
                anchors.fill: parent
                anchors.leftMargin: Tokens.s3
                anchors.rightMargin: Tokens.s3
                spacing: Tokens.s2

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.hasNotice ? "info"
                        : root.showsSnap ? "center_focus_strong" : "pan_tool"
                    iconSize: Tokens.fBody
                    color: root.hasNotice ? Tokens.ink : Tokens.inkMuted
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.coachText
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    font.weight: root.hasNotice || root.showsSnap ? Font.DemiBold : Font.Normal
                    color: Tokens.inkDim
                    elide: Text.ElideRight
                }
            }
        }

        // A single paper instrument plate. Every utility action uses the same
        // square footprint and hairline; only active mirror state inverts.
        Rectangle {
            id: dock
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: dockRow.implicitWidth + Tokens.s3 * 2
            implicitHeight: root.controlHeight + Tokens.s2 * 2
            radius: Tokens.radius * 2
            color: Tokens.paper
            border.width: Tokens.border
            border.color: Tokens.line
            enabled: root.ready
            opacity: root.dockIn
            visible: opacity > 0
            transform: Translate { y: (1 - root.dockIn) * Tokens.s5 }
            HoverHandler {
                id: dockHover
            }
            // The plate is not picture: a press between its buttons must not
            // start a drag of the wallpaper, and a quick second click there
            // must not read as the picture's double-click reset.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            RowLayout {
                id: dockRow
                anchors.centerIn: parent
                spacing: Tokens.s1

                DockButton {
                    symbol: "remove"
                    tooltip: Translation.tr("Zoom out")
                    enabled: root.target.zoom > WallpaperFraming.zoomMin + 0.0001
                    onClicked: root.zoomBy(1 / 1.1, 0, 0)
                }

                Rectangle {
                    id: readout
                    Layout.preferredWidth: Tokens.s7 + Tokens.s4 + Tokens.s1
                    implicitHeight: root.controlHeight
                    radius: Tokens.radius
                    color: readoutArea.pressed && readoutArea.enabled ? Tokens.tint16
                        : readoutArea.containsMouse && readoutArea.enabled ? Tokens.tint10 : Tokens.tint5
                    border.width: Tokens.border
                    border.color: Tokens.lineSoft
                    opacity: root.target.zoom > WallpaperFraming.zoomMin + 0.0001 ? 1 : 0.55

                    StyledText {
                        anchors.centerIn: parent
                        text: String(Math.round(WallpaperLayout.liveZoom * 100)) + "%"
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fBody
                        font.weight: Font.DemiBold
                        color: Tokens.ink
                    }
                    MouseArea {
                        id: readoutArea
                        anchors.fill: parent
                        enabled: root.target.zoom > WallpaperFraming.zoomMin + 0.0001
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.zoomTo(WallpaperFraming.zoomMin)
                    }
                    StyledToolTip {
                        requireOverlay: false
                        extraVisibleCondition: readoutArea.containsMouse
                        text: Translation.tr("Back to 100%")
                    }
                }

                DockButton {
                    symbol: "add"
                    tooltip: Translation.tr("Zoom in")
                    enabled: root.target.zoom < WallpaperFraming.zoomMax - 0.0001
                    onClicked: root.zoomBy(1.1, 0, 0)
                }

                DockDivider {}

                DockButton {
                    symbol: "rotate_left"
                    tooltip: Translation.tr("Turn left")
                    onClicked: WallpaperLayout.rotate(root.screenName, -1)
                }
                DockButton {
                    symbol: "rotate_right"
                    tooltip: Translation.tr("Turn right")
                    onClicked: WallpaperLayout.rotate(root.screenName, 1)
                }
                DockButton {
                    symbol: "flip"
                    toggled: WallpaperLayout.liveFlipH
                    tooltip: Translation.tr("Mirror horizontally")
                    onClicked: WallpaperLayout.flip(root.screenName, "horizontal")
                }
                DockButton {
                    symbol: "flip"
                    symbolRotation: 90
                    toggled: WallpaperLayout.liveFlipV
                    tooltip: Translation.tr("Mirror vertically")
                    onClicked: WallpaperLayout.flip(root.screenName, "vertical")
                }

                DockDivider {}

                DockButton {
                    symbol: "center_focus_strong"
                    tooltip: Translation.tr("Centre")
                    enabled: Math.abs(root.target.x) > 0.0005 || Math.abs(root.target.y) > 0.0005
                    onClicked: WallpaperLayout.centre(root.screenName)
                }

                RyokuUi.Btn {
                    Layout.leftMargin: Tokens.s1
                    Layout.preferredHeight: root.controlHeight
                    text: Translation.tr("Reset")
                    armed: !root.identity
                    motionEnabled: !Tokens.reduceMotion
                    onAct: WallpaperLayout.resetFraming(root.screenName)
                }
            }
        }
    }

    component DockDivider: Rectangle {
        Layout.leftMargin: Tokens.s1
        Layout.rightMargin: Tokens.s1
        Layout.preferredWidth: Tokens.border
        Layout.preferredHeight: root.controlHeight - Tokens.s2
        color: Tokens.lineSoft
    }

    component DockButton: Rectangle {
        id: button
        property string symbol: ""
        property real symbolRotation: 0
        property bool toggled: false
        property string tooltip: ""
        signal clicked()

        Layout.preferredWidth: root.controlHeight
        Layout.preferredHeight: root.controlHeight
        radius: Tokens.radius
        opacity: enabled ? 1 : 0.35
        color: button.toggled ? Tokens.bone
            : buttonArea.pressed && button.enabled ? Tokens.tint16
            : buttonArea.containsMouse && button.enabled ? Tokens.tint10 : "transparent"
        border.width: Tokens.border
        border.color: button.toggled ? Tokens.bone
            : buttonArea.containsMouse && button.enabled ? Tokens.lineStrong : Tokens.line

        Behavior on color {
            enabled: !Tokens.reduceMotion
            ColorAnimation { duration: Tokens.snap }
        }
        Behavior on border.color {
            enabled: !Tokens.reduceMotion
            ColorAnimation { duration: Tokens.snap }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: button.symbol
            rotation: button.symbolRotation
            iconSize: Tokens.fValue
            color: button.toggled ? Tokens.inkOnBone : Tokens.inkDim
        }
        // An exclusive grab: a click that drifts a few pixels on a touchpad
        // still lands, where a passive TapHandler would cancel it.
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            enabled: button.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
        StyledToolTip {
            requireOverlay: false
            extraVisibleCondition: buttonArea.containsMouse
            text: button.tooltip
        }
    }
}
