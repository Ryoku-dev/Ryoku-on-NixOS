pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"

// One desktop widget kind for the whole vendored iRiS roster. It is the slot
// content Ryoku's WidgetSlot measures and frames, so the slot's colour push and
// backing land on exactly this item.
//
//   kind "face"   — a hidden IrisFaceProvider builds the real inir widget as a
//                   data source and only its own irisFace is rendered here.
//   kind "canvas" — a visible IrisCanvasProvider renders the whole upstream
//                   widget (customImage, editorial, visualizer, …) at the origin.
//
// Style is per widget (widgets.json <prefix>Style), never the global
// iris.appearance.frontend: "inir" draws upstream, "ryoku" adds the slot's
// backing + geometry and, for faces (and any widget that reads the iRiS ink
// tokens), Ryoku ink. Colour modes ride the slot's inkColorA: Auto keeps the
// widget's own colouring, Fixed pins ink+accent, Gradient is masked by the slot.
Item {
    id: adapter

    property string faceId: "clock"
    property string prefix: "irisClock"
    property string kind: "face"          // "face" | "canvas"
    property var screen: null
    property real hostX: 0
    property real hostY: 0
    property real scaleCfg: 1
    property string sizeCfg: ""

    // Pushed by WidgetSlot for the Fixed colour mode (hex or "").
    property string inkColorA: ""

    readonly property bool ryokuStyle: Config[adapter.prefix + "Style"] === "ryoku"
    readonly property color _override: adapter.inkColorA.length > 0 ? adapter.inkColorA : "transparent"

    readonly property var _opts: {
        const raw = Config[adapter.prefix + "Opts"] || "";
        if (raw.length === 0)
            return ({});
        try {
            const parsed = JSON.parse(raw);
            return (parsed && typeof parsed === "object") ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }

    readonly property int _screenW: adapter.screen ? adapter.screen.width : 1920
    readonly property int _screenH: adapter.screen ? adapter.screen.height : 1080
    readonly property string _outputName: adapter.screen ? adapter.screen.name : ""

    implicitWidth: adapter.kind === "canvas"
        ? (canvasLoader.item ? canvasLoader.item.implicitWidth : 240)
        : (faceProv.item && faceProv.item.widget ? faceProv.item.widget.irisFaceWidth : 170)
    implicitHeight: adapter.kind === "canvas"
        ? (canvasLoader.item ? canvasLoader.item.implicitHeight : 160)
        : (faceProv.item && faceProv.item.widget ? faceProv.item.widget.irisFaceHeight : 170)

    // ── face path ────────────────────────────────────────────────────────────
    Loader {
        id: faceProv
        active: adapter.kind === "face"
        sourceComponent: IrisFaceProvider {
            faceId: adapter.faceId
            screenW: adapter._screenW
            screenH: adapter._screenH
            outputName: adapter._outputName
            hostX: adapter.hostX
            hostY: adapter.hostY
            ryokuStyle: adapter.ryokuStyle
            inkOverride: adapter._override
            accentOverride: adapter._override
            sizeOverride: adapter.sizeCfg
            scaleOverride: adapter.scaleCfg
            radiusOverride: Config[adapter.prefix + "Radius"]
            optionOverrides: adapter._opts
        }
    }
    Loader {
        id: face
        anchors.fill: parent
        active: adapter.kind === "face" && faceProv.item !== null && faceProv.item.widget !== null
        sourceComponent: (faceProv.item && faceProv.item.widget) ? faceProv.item.widget.irisFace : null
    }
    // The Ryoku skin hollows the face's own plate so the slot backing shows.
    Binding {
        target: face.item
        property: "ryokuBare"
        value: adapter.ryokuStyle
        when: face.item !== null
    }

    // ── canvas path ──────────────────────────────────────────────────────────
    Loader {
        id: canvasLoader
        anchors.fill: parent
        active: adapter.kind === "canvas"
        sourceComponent: IrisCanvasProvider {
            faceId: adapter.faceId
            screenW: adapter._screenW
            screenH: adapter._screenH
            outputName: adapter._outputName
            hostX: adapter.hostX
            hostY: adapter.hostY
            ryokuStyle: adapter.ryokuStyle
            inkOverride: adapter._override
            accentOverride: adapter._override
            scaleOverride: adapter.scaleCfg
            radiusOverride: Config[adapter.prefix + "Radius"]
            // Match the slot card's resolved rounding so the Ryoku custom-image
            // surface clips its media to the same shape (Theme.radius = square).
            slotRadius: Config[adapter.prefix + "Radius"] >= 0 ? Config[adapter.prefix + "Radius"] : Theme.radius
            optionOverrides: adapter._opts
        }
    }
}
