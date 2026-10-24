pragma ComponentBehavior: Bound
import QtQuick

// The audio spectrum as a living edge field: twelve sectors flow along chosen
// screen edges -- a rail, an open frame, or a joined perimeter -- as one organic
// current instead of a row of bars. Geometry and colour only: the caller folds
// and eases the bands (see lib/aura.js) and passes the twelve live sectors plus
// their peaks; the shader paints from there.
//
// It is the desktop's `aura` look and the Hub preview's twin, exactly as
// SpectrumField is for the other looks: one item, one shader, both surfaces, so
// neither can drift. Fill it with the surface the field belongs to. `edges`
// names which screen edges carry the field and `depth` is how far inward the
// current reaches, in px, so left+right rails, a bottom horizon, or all four
// edges as a joined frame are the same single pass.
Item {
    id: root

    // Twelve eased sector levels, 0..1, then twelve decaying peaks. The field
    // reads both: the live value drives the body, the peak the pulse.
    property var bands: []
    property var peaks: []

    // Which screen edges carry the field: a list of "top", "right", "bottom",
    // "left", and how far inward the current reaches in px.
    property var edges: ["left", "right"]
    property real depth: 180

    // Composition along each edge: the share it spans, where that span sits
    // (0..1; the anchor mirrors on the right/bottom edges so it reads from the
    // edge's own start), the soft fade at the ends, and the radius the field
    // rounds to at the screen corners. `join` "auto" blends two full-span
    // adjacent edges into one continuous field; "separate" keeps each its rail.
    property real span: 1.0
    property real position: 0.5
    property real taper: 0.14
    property real cornerRadius: 24
    property string join: "auto"
    property real cornerBlend: 0.55
    property string flow: "clockwise"

    // The four vocabularies of the look, by name: the material the current is
    // cut from, the shape it moves in, the effect riding it, and how the
    // palette walks along the edge.
    property string material: "silk"
    readonly property int materialIndex: Math.max(0,
        ["silk", "aurora", "contour", "liquid"].indexOf(root.material))
    property string shape: "flow"
    readonly property int shapeIndex: Math.max(0,
        ["flow", "ribbon", "cells", "filament"].indexOf(root.shape))
    property string effect: "clean"
    readonly property int effectIndex: Math.max(0,
        ["clean", "shimmer", "echo", "prism", "bloom", "caustic", "afterglow"]
            .indexOf(root.effect))
    property string colorMode: "flow"
    readonly property int colorModeIndex: Math.max(0,
        ["flow", "spectrum", "pulse", "static"].indexOf(root.colorMode))

    // Body and light: how solid the current reads, how bright its crest, how
    // wide the halo spills, and the share of the spectrum the edge walks.
    property real bodyOpacity: 0.32
    property real crestStrength: 0.9
    property real glow: 0.52
    property real glowSpread: 0.48
    property real audioRange: 0.78
    property real thickness: 0.22
    property real detail: 0.42
    property real effectStrength: 0.38

    // The drives the shader hands each part of the band.
    property real bassDrive: 0.88
    property real trebleDrive: 0.68
    property real transientStrength: 0.9
    property real beatGlow: 0.64

    // Motion and activity, eased by the caller: the phase turns the field,
    // energy is its loudness, pulse its beat, onset its transients. Sensitivity
    // scales how hard the spectrum pushes, compression gates the levels, and
    // speed/idleMotion keep the current drifting when nothing plays.
    property real phase: 0
    property real idleMotion: 0.14
    property real energy: 0
    property real pulse: 0
    property real onset: 0
    property real compression: 0.12
    property real sensitivity: 1.0
    property real pulseStrength: 0.9
    property real colorSpeed: 0.35

    // The triadic ramp: three colours the palette cycles through along the edge.
    property color primaryColor: "#b5a0ff"
    property color secondaryColor: "#64dbcf"
    property color tertiaryColor: "#ffb2cf"

    property bool active: true

    readonly property bool drawing: root.active && root.bands.length >= 2
        && root.width > 1 && root.height > 1

    function hasEdge(name) {
        var e = root.edges;
        return e && e.indexOf ? e.indexOf(name) >= 0 : false;
    }

    // A per-edge reach, clamped so a depth larger than the screen never lets
    // one rail cover the opposite edge.
    function depthFor(axisPx) {
        return Math.max(24, Math.min(root.depth, axisPx * 0.45));
    }

    function slot(src, base) {
        var s = (src && src.length) ? src : [];
        return Qt.vector4d(s[base] || 0, s[base + 1] || 0,
                           s[base + 2] || 0, s[base + 3] || 0);
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: root.drawing
        blending: true
        fragmentShader: Qt.resolvedUrl("shaders/aura.frag.qsb")

        property vector2d resolution: Qt.vector2d(width, height)
        property vector4d edges: Qt.vector4d(root.hasEdge("top") ? 1 : 0,
                                             root.hasEdge("right") ? 1 : 0,
                                             root.hasEdge("bottom") ? 1 : 0,
                                             root.hasEdge("left") ? 1 : 0)
        property vector4d depths: Qt.vector4d(root.depthFor(height),
                                              root.depthFor(width),
                                              root.depthFor(height),
                                              root.depthFor(width))
        property vector4d geometry: Qt.vector4d(root.span, root.position,
                                                root.taper, root.cornerRadius)
        property vector4d material: Qt.vector4d(root.thickness, root.detail,
                                                 root.glow, root.materialIndex)
        property vector4d appearance: Qt.vector4d(root.bodyOpacity, root.crestStrength,
                                                  root.glowSpread, root.audioRange)
        property vector4d response: Qt.vector4d(root.bassDrive, root.trebleDrive,
                                                 root.transientStrength, root.beatGlow)
        property vector4d effects: Qt.vector4d(root.effectIndex, root.effectStrength,
                                               root.colorModeIndex, root.shapeIndex)
        property vector4d topology: Qt.vector4d(root.join !== "separate" ? 1 : 0,
                                                 root.flow === "counterclockwise" ? -1 : 1,
                                                 root.cornerBlend, 0)
        property vector4d motion: Qt.vector4d(root.phase, root.idleMotion,
                                              root.colorSpeed, root.sensitivity)
        property vector4d activity: Qt.vector4d(root.energy,
                                                root.pulse * root.pulseStrength,
                                                root.onset, root.compression)
        property vector4d bandsA: root.slot(root.bands, 0)
        property vector4d bandsB: root.slot(root.bands, 4)
        property vector4d bandsC: root.slot(root.bands, 8)
        property vector4d peaksA: root.slot(root.peaks, 0)
        property vector4d peaksB: root.slot(root.peaks, 4)
        property vector4d peaksC: root.slot(root.peaks, 8)
        property vector4d primaryColor: Qt.vector4d(root.primaryColor.r, root.primaryColor.g,
                                                    root.primaryColor.b, 1)
        property vector4d secondaryColor: Qt.vector4d(root.secondaryColor.r, root.secondaryColor.g,
                                                      root.secondaryColor.b, 1)
        property vector4d tertiaryColor: Qt.vector4d(root.tertiaryColor.r, root.tertiaryColor.g,
                                                     root.tertiaryColor.b, 1)
    }
}
