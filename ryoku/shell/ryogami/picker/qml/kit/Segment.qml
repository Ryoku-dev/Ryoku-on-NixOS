import QtQuick

// A large section title. Fraunces sets it, the way a page title does.
Text {
    id: segment

    property string label: ""
    property real reveal: 1

    text: segment.label
    font.family: Theme.display
    font.pixelSize: Theme.fontSegment
    color: Theme.withAlpha(Theme.surfaceText, segment.reveal)
    renderType: Text.NativeRendering
    elide: Text.ElideRight
}
