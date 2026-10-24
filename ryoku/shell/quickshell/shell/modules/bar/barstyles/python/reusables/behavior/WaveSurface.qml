import QtQuick

// The serpantinum liquid wave drawn by wave.frag on the GPU. Drop-in for the
// Canvas that used to rasterise the same bezier every WaveTick: the caller
// binds the same numbers it used to hand to the paint, and only this item's
// rectangle repaints, with no JS path building and no image upload. A flat
// fill (amp 0) changes no bound property, so a full battery or an idle pill
// commits nothing at all. Uniform names mirror wave.frag; Qt binds color
// properties straight to the shader's vec4 uniforms.
ShaderEffect {
    id: root

    property real sizeX: width
    property real sizeY: height
    // 0..1 along the fill axis; the surface crosses at fill * span.
    property real fill: 0
    // Crest height in px; 0 draws a flat edge.
    property real amp: 0
    // Radians, from the caller's WaveClock.
    property real phase: 0
    // Corner radius of the clipped plate in px.
    property real radius: 0
    // 1 waves along y (a tile filled from the left); 0 along x (a pill).
    property real horizontal: 0
    property real alpha: 0.95
    property color colorTop
    property color colorBottom

    blending: true
    // Resolved here, not in the caller: a bare relative path would bind
    // against whichever file instantiates the surface, and the consumers sit
    // at three different depths under the style root.
    fragmentShader: Qt.resolvedUrl("../../shaders/wave.frag.qsb")
}
