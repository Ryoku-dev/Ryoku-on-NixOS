import QtQuick

Text {
    id: icon

    property string glyph: ""
    property real base: Theme.typeScale.head

    text: icon.glyph
    font.family: Theme.icon
    font.pixelSize: Theme.fs(icon.base)
    color: Theme.surfaceText
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
