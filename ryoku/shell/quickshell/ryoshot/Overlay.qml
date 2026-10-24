import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "lib/coords.js" as Coords
import "lib/capture-backend.js" as CaptureBackend
import "Singletons"
import Ryoku.Ui.Singletons

Item {
    id: overlay
    anchors.fill: parent

    required property var screenData
    property var globalSel: null
    property bool capturing: false
    property bool ready: false
    property bool resizable: false
    property bool eyedropArmed: false
    // The region-selector front draws its crosshair and reads the pointer here;
    // pickMode arms the compositor-neutral colour sample (from the frozen plate).
    property bool frontActive: false
    property bool pickMode: false

    property var model: null
    property var draft: null
    property int annRevision: 0
    property bool textEditing: false
    property var selectedIndex: null
    property var moveOffset: null
    property var hoverWindow: null

    signal pressedAt(real gx, real gy, int mods)
    signal movedTo(real gx, real gy, int mods)
    signal hovered(real gx, real gy)
    signal released()
    signal frozen()
    signal textChanged(string t)
    signal textCommitted()
    signal wheeled(int dir)
    signal resizeStarted(string role, real gx, real gy)
    signal resizeMoved(real gx, real gy)
    signal resizeEnded()
    signal sampled(color c)

    readonly property int sx: screenData.x
    readonly property int sy: screenData.y
    readonly property string scrName: screenData.name

    readonly property var localSel: globalSel
        ? Coords.intersectRect(globalSel, { x: sx, y: sy, width: width, height: height })
        : null

    // grim renders the same output the compositor would hand screencopy, so the
    // fallback frame lines up pixel for pixel with the layer surface above it.
    readonly property bool forceFallback: CaptureBackend.shouldUseGrim(
        Quickshell.env("RYOSHOT_FORCE_FALLBACK"),
        Quickshell.env("XDG_CURRENT_DESKTOP"),
        Quickshell.env("NIRI_SOCKET"))
    property bool fallbackActive: false
    readonly property string fallbackPath: "/tmp/ryoshot-fallback-" + scrName + ".png"

    function selectionBox() {
        if (selectedIndex === null || !model
            || selectedIndex < 0 || selectedIndex >= model.items.length) return null;
        var a = model.items[selectedIndex];
        var off = moveOffset || { x: 0, y: 0 };
        var xs = a.points.map(function (p) { return p.x; });
        var ys = a.points.map(function (p) { return p.y; });
        var x0 = Math.min.apply(null, xs), x1 = Math.max.apply(null, xs);
        var y0 = Math.min.apply(null, ys), y1 = Math.max.apply(null, ys);
        var pad = Math.max((a.width || 4), 6);
        if (a.type === "text") {
            var size = a.size || 16;
            x1 = x0 + Math.max((a.text ? a.text.length : 1) * size * 0.6, size);
            y1 = y0 + size * 1.4;
            pad = 4;
        }
        return {
            x: x0 - sx + off.x - pad,
            y: y0 - sy + off.y - pad,
            w: (x1 - x0) + pad * 2,
            h: (y1 - y0) + pad * 2
        };
    }

    readonly property var selBox: { annRevision; return selectionBox(); }

    Item {
        id: scene
        anchors.fill: parent

        // The captured pixels with no annotation over them. The effect layer
        // samples this, the export samples the whole scene.
        Item {
            id: plate
            anchors.fill: parent

            Loader {
                id: shotLoader
                anchors.fill: parent
                active: !overlay.forceFallback
                sourceComponent: Component {
                    ScreencopyView {
                        anchors.fill: parent
                        captureSource: overlay.screenData
                        live: false
                        paintCursor: false
                        visible: !overlay.fallbackActive
                    }
                }
            }

            Image {
                id: fallbackImage
                anchors.fill: parent
                visible: overlay.fallbackActive
                cache: false
                fillMode: Image.Stretch
                onStatusChanged: {
                    if (status === Image.Ready && !overlay.ready) {
                        overlay.fallbackActive = true;
                        overlay.ready = true;
                        overlay.frozen();
                    } else if (status === Image.Error) {
                        console.error("ryoshot: grim fallback failed to load for " + overlay.scrName);
                    }
                }
            }
        }

        EffectLayer {
            anchors.fill: parent
            frame: plate
            sx: overlay.sx
            sy: overlay.sy
            model: overlay.model
            draft: overlay.draft
            revision: overlay.annRevision
        }

        AnnLayer {
            anchors.fill: parent
            sx: overlay.sx
            sy: overlay.sy
            model: overlay.model
            draft: overlay.draft
            revision: overlay.annRevision
            selectedIndex: overlay.selectedIndex
            moveOffset: overlay.moveOffset
        }
    }

    Process {
        id: grimProc
        command: ["ryoku-cmd-grim", "-o", overlay.scrName, overlay.fallbackPath]
        onExited: (code) => {
            if (code !== 0) {
                console.error("ryoshot: grim fallback exited " + code + " for " + overlay.scrName);
                return;
            }
            fallbackImage.source = "file://" + overlay.fallbackPath + "?t=" + Date.now();
        }
    }

    function startFallback() {
        if (overlay.fallbackActive || grimProc.running) return;
        console.log(overlay.forceFallback
            ? "ryoshot: using grim capture for " + overlay.scrName
            : "ryoshot: no screencopy frame for " + overlay.scrName + ", falling back to grim");
        grimProc.running = true;
    }

    Timer {
        id: capTimer
        interval: 50
        repeat: true
        running: !overlay.forceFallback
        property int tries: 0
        onTriggered: {
            tries += 1;
            var shot = shotLoader.item;
            if (shot && shot.hasContent) {
                running = false;
                overlay.ready = true;
                overlay.frozen();
            } else if (!shot || tries > 60) {
                running = false;
                overlay.startFallback();
            } else {
                shot.captureFrame();
            }
        }
    }

    Component.onCompleted: if (overlay.forceFallback) overlay.startFallback()

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        visible: overlay.ready && overlay.localSel === null
    }

    Item {
        anchors.fill: parent
        visible: overlay.ready && overlay.localSel !== null
        Rectangle {
            color: Theme.scrim
            x: 0; y: 0; width: parent.width
            height: overlay.localSel ? overlay.localSel.y : 0
        }
        Rectangle {
            color: Theme.scrim
            x: 0; width: parent.width
            y: overlay.localSel ? overlay.localSel.y + overlay.localSel.h : 0
            height: overlay.localSel ? parent.height - (overlay.localSel.y + overlay.localSel.h) : 0
        }
        Rectangle {
            color: Theme.scrim
            x: 0
            y: overlay.localSel ? overlay.localSel.y : 0
            width: overlay.localSel ? overlay.localSel.x : 0
            height: overlay.localSel ? overlay.localSel.h : 0
        }
        Rectangle {
            color: Theme.scrim
            x: overlay.localSel ? overlay.localSel.x + overlay.localSel.w : 0
            y: overlay.localSel ? overlay.localSel.y : 0
            width: overlay.localSel ? parent.width - (overlay.localSel.x + overlay.localSel.w) : 0
            height: overlay.localSel ? overlay.localSel.h : 0
        }
    }

    // Crosshair guides that track the pointer while the front chooses a region,
    // shown only on the monitor the cursor is over.
    Item {
        anchors.fill: parent
        visible: overlay.frontActive && overlay.ready && input.containsMouse
        z: 15
        Rectangle {
            x: Math.round(input.mouseX)
            y: 0
            width: 1
            height: parent.height
            color: Theme.accent
            opacity: 0.35
        }
        Rectangle {
            x: 0
            y: Math.round(input.mouseY)
            width: parent.width
            height: 1
            color: Theme.accent
            opacity: 0.35
        }
    }

    // Colour-pick loupe: a magnified window on the frozen plate under the pointer,
    // hyprpicker-style, but sampled from ScreencopyView so it works on any
    // compositor. The pixel is read on click (see sampleAt).
    Item {
        id: loupe
        readonly property int box: 128
        readonly property real zoom: 8
        visible: overlay.pickMode && overlay.ready && input.containsMouse
        z: 30
        width: box
        height: box
        x: Math.max(8, Math.min(input.mouseX + 22, overlay.width - box - 8))
        y: Math.max(8, Math.min(input.mouseY + 22, overlay.height - box - 8))

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.panelSolid
            border.color: Theme.hair
            border.width: 1
            clip: true

            ShaderEffectSource {
                anchors.centerIn: parent
                width: loupe.box - 8
                height: loupe.box - 8
                sourceItem: plate
                smooth: false
                live: overlay.pickMode
                sourceRect: Qt.rect(input.mouseX - (loupe.box / loupe.zoom) / 2,
                                    input.mouseY - (loupe.box / loupe.zoom) / 2,
                                    loupe.box / loupe.zoom, loupe.box / loupe.zoom)
            }

            Rectangle {
                anchors.centerIn: parent
                width: loupe.zoom
                height: loupe.zoom
                color: "transparent"
                border.color: Theme.accent
                border.width: 1
            }
        }
    }

    Item {
        id: chrome
        visible: overlay.ready && overlay.localSel !== null
        x: overlay.localSel ? overlay.localSel.x : 0
        y: overlay.localSel ? overlay.localSel.y : 0
        width: overlay.localSel ? overlay.localSel.w : 0
        height: overlay.localSel ? overlay.localSel.h : 0

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Theme.accent
            border.width: 1.5
        }

        Text {
            text: overlay.globalSel
                ? Math.round(overlay.globalSel.w) + "\u00d7" + Math.round(overlay.globalSel.h)
                : ""
            color: Theme.accent
            font.family: Theme.mono
            font.pixelSize: 13
            x: 0
            y: -height - 4
        }
    }

    ResizeHandles {
        anchors.fill: parent
        // above the drawing MouseArea, or a grip press would start a stroke
        z: 20
        visible: overlay.ready && overlay.resizable && overlay.globalSel !== null
        globalRect: overlay.globalSel
        sx: overlay.sx
        sy: overlay.sy
        onStarted: (role, gx, gy) => overlay.resizeStarted(role, gx, gy)
        onMoved: (gx, gy) => overlay.resizeMoved(gx, gy)
        onEnded: overlay.resizeEnded()
    }

    Item {
        id: winHighlight
        readonly property var hw: overlay.hoverWindow
            ? Coords.intersectRect(overlay.hoverWindow, { x: overlay.sx, y: overlay.sy, width: overlay.width, height: overlay.height })
            : null
        visible: overlay.ready && overlay.globalSel === null && hw !== null
        x: hw ? hw.x : 0
        y: hw ? hw.y : 0
        width: hw ? hw.w : 0
        height: hw ? hw.h : 0

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
            border.color: Theme.accent
            border.width: 2.5
            antialiasing: true
        }
    }

    Item {
        id: annSelection
        visible: overlay.ready && overlay.selBox !== null
        x: overlay.selBox ? overlay.selBox.x : 0
        y: overlay.selBox ? overlay.selBox.y : 0
        width: overlay.selBox ? overlay.selBox.w : 0
        height: overlay.selBox ? overlay.selBox.h : 0

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Theme.accent
            border.width: 1
            antialiasing: true
        }

        Repeater {
            model: [
                { hx: 0, hy: 0 },
                { hx: 1, hy: 0 },
                { hx: 0, hy: 1 },
                { hx: 1, hy: 1 }
            ]
            Rectangle {
                required property var modelData
                width: 7; height: 7
                radius: 1
                color: Theme.accent
                x: modelData.hx * (annSelection.width - width)
                y: modelData.hy * (annSelection.height - height)
            }
        }
    }

    ClipGrab {
        id: exportClip
        source: scene
        ready: overlay.ready
        rect: overlay.localSel
    }

    ClipGrab {
        id: regionClip
        source: scene
        ready: overlay.ready
        rect: null
    }

    ClipGrab {
        id: plateClip
        source: plate
        ready: overlay.ready
        rect: null
    }

    /** Saves the selected region of this monitor, annotations included. */
    function grabExport(path, cb, targetSize) { exportClip.grab(path, cb, targetSize || null); }

    /** Saves an arbitrary local rect of the annotated scene, for OCR crops. */
    function grabRegion(rect, path, cb) {
        regionClip.rect = rect;
        regionClip.grab(path, cb);
    }

    /** Saves an arbitrary local rect of the raw capture, for palette sampling. */
    function grabPlate(rect, path, cb, targetSize) {
        plateClip.rect = rect;
        plateClip.grab(path, cb, targetSize || null);
    }

    // The eyedropper reads one pixel back through imagemagick because QML has no
    // path from a grab result to a colour value.
    Process {
        id: pickProc
        stdout: StdioCollector { id: pickOut }
        function read() {
            command = ["magick", "/tmp/ryoshot-pick.png", "-alpha", "off", "-format", "#%[hex:p{0,0}]", "info:"];
            running = true;
        }
        onExited: (code) => {
            var hex = pickOut.text.trim();
            if (code === 0 && /^#[0-9A-Fa-f]{6}$/.test(hex)) overlay.sampled(hex);
            else console.log("ryoshot: colour sample failed, exit " + code + " value " + JSON.stringify(hex));
        }
    }

    function sampleAt(lx, ly) {
        plateClip.rect = { x: Math.max(0, lx - 0.5), y: Math.max(0, ly - 0.5), w: 1, h: 1 };
        plateClip.grab("/tmp/ryoshot-pick.png", function (ok) {
            if (ok) pickProc.read();
        }, Qt.size(1, 1));
    }

    MouseArea {
        id: input
        anchors.fill: parent
        enabled: overlay.ready
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: overlay.eyedropArmed ? Qt.PointingHandCursor : Qt.CrossCursor
        onPressed: (m) => {
            if (overlay.eyedropArmed || overlay.pickMode) { overlay.sampleAt(m.x, m.y); return; }
            overlay.pressedAt(m.x + overlay.sx, m.y + overlay.sy, m.modifiers);
        }
        onPositionChanged: (m) => {
            if (overlay.capturing) overlay.movedTo(m.x + overlay.sx, m.y + overlay.sy, m.modifiers);
            else overlay.hovered(m.x + overlay.sx, m.y + overlay.sy);
        }
        onReleased: { if (!overlay.eyedropArmed && !overlay.pickMode) overlay.released(); }
        onWheel: (w) => {
            if (w.angleDelta.y === 0) return;
            overlay.wheeled(w.angleDelta.y > 0 ? 1 : -1);
            w.accepted = true;
        }
    }

    TextInput {
        id: textEdit
        readonly property bool mine: overlay.textEditing && overlay.draft
            && overlay.draft.type === "text" && overlay.localSel !== null
            && (overlay.draft.points[0].x >= overlay.sx) && (overlay.draft.points[0].x < overlay.sx + overlay.width)
            && (overlay.draft.points[0].y >= overlay.sy) && (overlay.draft.points[0].y < overlay.sy + overlay.height)
        visible: mine
        enabled: mine
        x: mine ? overlay.draft.points[0].x - overlay.sx : 0
        y: mine ? overlay.draft.points[0].y - overlay.sy : 0
        color: mine ? overlay.draft.color : "transparent"
        font.family: Theme.ui
        font.pixelSize: mine ? overlay.draft.size : 16
        renderType: Text.NativeRendering
        cursorVisible: mine
        autoScroll: false
        onTextEdited: overlay.textChanged(text)
        onMineChanged: if (mine) { text = overlay.draft.text || ""; forceActiveFocus(); }
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { overlay.textCommitted(); e.accepted = true; }
            else if (e.key === Qt.Key_Escape) { e.accepted = false; }
        }
    }
}
