pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

// The floating recording island, ported from iNiR's recording OSD into the Ryoku
// look. A standalone layer-shell surface, not part of the frame, so it is the one
// recording HUD on every bar style. It shows only while a capture runs (or during
// the pre-record countdown): a crisp Ryoku card -- the shell surface + hairline
// outline, matching the frame-edge cards rather than a blob -- carrying a grab
// handle, a pulsing record dot, the elapsed clock (or the countdown number), the
// live audio state, and a stop button. Drag it anywhere; let go and it snaps to
// the nearest screen edge, turning vertical on a side edge. Save + notify on stop
// is the backend's job; this surface never opens an editor.
PanelWindow {
    id: win

    required property var modelData

    // The work area on this output, in logical pixels. The layer surface respects
    // exclusive zones (exclusiveZone 0 below), so win.width/height already exclude
    // the bars, the dock and the frame band on every bar style. modelData's sizes
    // are the full physical output and must NOT position the pill -- on a fractional
    // scale (1.0667 here) that pushes it under the bottom edge.
    readonly property real areaW: win.width
    readonly property real areaH: win.height

    readonly property bool shown: Recorder.anyActive || Recorder.countingDown
    readonly property bool counting: Recorder.countingDown && !Recorder.anyActive

    // audio state the pill reflects: the live mode while recording, else the
    // configured toggles so the pre-record countdown already shows what it will be.
    readonly property string audioMode: Recorder.anyActive ? Recorder.activeAudioMode
        : (Recorder.optDesktopAudio && Recorder.optMic ? "both"
            : Recorder.optDesktopAudio ? "system"
            : Recorder.optMic ? "microphone" : "none")
    readonly property bool usesSystem: audioMode === "system" || audioMode === "both"
    readonly property bool usesMic: audioMode === "microphone" || audioMode === "both"

    screen: modelData
    visible: win.shown || win.reveal > 0.01
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ryoku-record-island"

    anchors { top: true; bottom: true; left: true; right: true }

    // only the pill takes input; the rest of the screen stays click-through.
    mask: Region { item: card }

    readonly property real margin: 14
    // which edge the island rests on; a side edge turns the pill vertical.
    property string edge: "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"

    // a pulse the record dot rides while live, and an "arming" pulse in the count.
    property real pulse: 1
    SequentialAnimation on pulse {
        running: win.shown
        loops: Animation.Infinite
        NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutSine }
    }

    // ── position. Before the user drags, the pill sits bottom-centre of the work
    // area as a live binding (defaultX/Y), so it is placed correctly the instant the
    // surface has a size -- there is no seed timing to miss. A drag latches `placed`
    // and px/py take over; clampX/clampY keep it fully inside the work area,
    // re-evaluated whenever that area changes (a bar reveal, an output or scale
    // change), so it can never end up under an edge.
    property real px: 0
    property real py: 0
    property bool placed: false
    property bool dragging: false

    function clampX(x) { return Math.max(win.margin, Math.min(win.areaW - card.width - win.margin, x)); }
    function clampY(y) { return Math.max(win.margin, Math.min(win.areaH - card.height - win.margin, y)); }

    readonly property real defaultX: (win.areaW > 0 && card.width > 0) ? Math.max(win.margin, (win.areaW - card.width) / 2) : win.margin
    readonly property real defaultY: (win.areaH > 0 && card.height > 0) ? Math.max(win.margin, win.areaH - card.height - win.margin) : win.margin
    readonly property real cx: win.placed ? win.clampX(win.px) : win.defaultX
    readonly property real cy: win.placed ? win.clampY(win.py) : win.defaultY

    // snap to the nearest work-area edge on release, then clamp along it.
    function snap() {
        const centerX = win.px + card.width / 2;
        const centerY = win.py + card.height / 2;
        const dl = centerX;
        const dr = win.areaW - centerX;
        const dt = centerY;
        const db = win.areaH - centerY;
        const m = Math.min(dl, dr, dt, db);
        win.edge = m === dl ? "left" : m === dr ? "right" : m === dt ? "top" : "bottom";
        Qt.callLater(function () {
            if (win.edge === "left")
                win.px = win.margin;
            else if (win.edge === "right")
                win.px = win.areaW - card.width - win.margin;
            else if (win.edge === "top")
                win.py = win.margin;
            else
                win.py = win.areaH - card.height - win.margin;
            win.px = win.clampX(win.px);
            win.py = win.clampY(win.py);
        });
    }

    // enter/exit: scale + fade. `shown` drives reveal; the window stays mapped
    // through the fade-out (visible tracks reveal), so the exit is never cut off.
    property real reveal: 0
    onShownChanged: win.reveal = win.shown ? 1 : 0
    // The island is lazy-built once a capture is already live, so `shown` is
    // already true at creation and onShownChanged never fires -- seed reveal here
    // so the pill fades in instead of staying at opacity 0.
    Component.onCompleted: win.reveal = win.shown ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

    Rectangle {
        id: card
        x: win.cx
        y: win.cy
        width: (win.vertical ? col.implicitWidth : row.implicitWidth) + 20
        height: (win.vertical ? col.implicitHeight : row.implicitHeight) + 14
        radius: Theme.radiusWindow
        color: Theme.surface
        border.width: Theme.borderWidth
        border.color: Theme.outline
        opacity: win.reveal
        scale: 0.9 + 0.1 * win.reveal
        transformOrigin: Item.Center

        Behavior on x { enabled: !win.dragging; NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }
        Behavior on y { enabled: !win.dragging; NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.InOutCubic } }
        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.InOutCubic } }


        // grab handle: a dot grid that drags the whole island. Release snaps to the
        // nearest edge. Reused for both orientations.
        component Grip: Item {
            implicitWidth: gripGrid.implicitWidth + 6
            implicitHeight: gripGrid.implicitHeight + 6
            Grid {
                id: gripGrid
                anchors.centerIn: parent
                columns: win.vertical ? 3 : 2
                rowSpacing: 3
                columnSpacing: 3
                Repeater {
                    model: 6
                    Rectangle {
                        required property int index
                        width: 3
                        height: 3
                        radius: 1.5
                        color: gripHov.hovered ? Theme.onSurface : Theme.onSurfaceVariant
                    }
                }
            }
            HoverHandler { id: gripHov; cursorShape: Qt.SizeAllCursor }
            DragHandler {
                target: null
                dragThreshold: 6
                property real sx: 0
                property real sy: 0
                onActiveChanged: {
                    if (active) {
                        sx = win.cx;
                        sy = win.cy;
                        win.px = sx;
                        win.py = sy;
                        win.placed = true;
                        win.dragging = true;
                    } else {
                        win.dragging = false;
                        win.snap();
                    }
                }
                onCentroidChanged: {
                    if (!active)
                        return;
                    win.px = win.clampX(sx + centroid.scenePosition.x - centroid.scenePressPosition.x);
                    win.py = win.clampY(sy + centroid.scenePosition.y - centroid.scenePressPosition.y);
                }
            }
        }

        // pulsing record dot.
        component Dot: Rectangle {
            width: 9
            height: 9
            radius: 4.5
            color: win.counting ? Theme.onSurfaceVariant : Theme.vermLit
            opacity: win.pulse
        }

        // the elapsed clock, or the countdown number before capture.
        component Clock: Text {
            text: win.counting ? Recorder.countdownSec : Recorder.elapsedText
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: 13
            font.features: ({ "tnum": 1 })
        }

        // a small round action button (stop).
        component IslandButton: Rectangle {
            id: ib
            property string glyph: ""
            property color tint: Theme.onSurface
            signal tapped()
            width: 26
            height: 26
            radius: 7
            color: ibTap.pressed ? Theme.threadBg : ibHov.hovered ? Theme.frameBg : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            GlyphIcon {
                anchors.centerIn: parent
                width: 14
                height: 14
                name: ib.glyph
                color: ib.tint
                stroke: 1.9
            }
            HoverHandler { id: ibHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: ibTap; onTapped: ib.tapped() }
        }

        // audio-state glyphs: desktop + mic, dimmed when that source is off. Hidden
        // during the countdown, where only the arming state matters.
        component AudioState: Row {
            spacing: 4
            visible: !win.counting
            GlyphIcon {
                anchors.verticalCenter: win.vertical ? undefined : parent.verticalCenter
                width: 13
                height: 13
                name: win.usesSystem ? "speaker" : "speaker-off"
                color: win.usesSystem ? Theme.onSurface : Theme.onSurfaceVariant
                stroke: 1.7
            }
            GlyphIcon {
                anchors.verticalCenter: win.vertical ? undefined : parent.verticalCenter
                width: 13
                height: 13
                name: win.usesMic ? "mic" : "mic-off"
                color: win.usesMic ? Theme.onSurface : Theme.onSurfaceVariant
                stroke: 1.7
            }
        }

        // horizontal layout (top / bottom edge).
        Row {
            id: row
            visible: !win.vertical
            anchors.centerIn: parent
            spacing: 8
            Grip { anchors.verticalCenter: parent.verticalCenter }
            Dot { anchors.verticalCenter: parent.verticalCenter }
            Clock { anchors.verticalCenter: parent.verticalCenter }
            IslandButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: Recorder.active
                glyph: Recorder.paused ? "play" : "pause"
                Accessible.name: Recorder.paused ? I18n.tr("Resume recording") : I18n.tr("Pause recording")
                onTapped: Recorder.togglePause()
            }
            AudioState { anchors.verticalCenter: parent.verticalCenter }
            IslandButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "stop"
                tint: Theme.vermLit
                onTapped: Recorder.stop()
            }
        }

        // vertical layout (left / right edge).
        Column {
            id: col
            visible: win.vertical
            anchors.centerIn: parent
            spacing: 8
            Grip { anchors.horizontalCenter: parent.horizontalCenter }
            Dot { anchors.horizontalCenter: parent.horizontalCenter }
            Clock { anchors.horizontalCenter: parent.horizontalCenter }
            IslandButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Recorder.active
                glyph: Recorder.paused ? "play" : "pause"
                Accessible.name: Recorder.paused ? I18n.tr("Resume recording") : I18n.tr("Pause recording")
                onTapped: Recorder.togglePause()
            }
            AudioState { anchors.horizontalCenter: parent.horizontalCenter }
            IslandButton {
                anchors.horizontalCenter: parent.horizontalCenter
                glyph: "stop"
                tint: Theme.vermLit
                onTapped: Recorder.stop()
            }
        }
    }
}
