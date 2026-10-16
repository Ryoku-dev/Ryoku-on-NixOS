import QtQuick
import Ryoku.Ui.Singletons

// One key cap in the shipped legend's vocabulary: a hairline rect with a mono
// glyph, no fill and no colour spent. Modifiers and keys look identical because
// Kit leans on type and space, not accent. The cap sizes to its glyph, so a
// multi-token label ("Num 1", "Page Up", "Vol +") reads without clipping while
// a single glyph stays square.
Rectangle {
    id: cap
    property string text: ""

    implicitHeight: 22
    implicitWidth: Math.max(cap.implicitHeight, label.implicitWidth + 2 * Tokens.s2)
    radius: Tokens.radius
    color: "transparent"
    border.width: Tokens.border
    border.color: Tokens.line

    Text {
        id: label
        anchors.centerIn: parent
        text: cap.text
        color: Tokens.inkDim
        font.family: Tokens.mono
        font.pixelSize: Tokens.fMicro
    }
}
