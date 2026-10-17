import QtQuick

// A small mono caps label: the sheet vocabulary for "what this block is".
Text {
    property var pal: null
    property real k: 1
    color: pal ? pal.inkMuted : "#b5a691"
    font.family: pal ? pal.mono : "monospace"
    font.pixelSize: Math.max(8, Math.round(9 * k))
    font.letterSpacing: Math.round(1.1 * k)
    font.weight: Font.Medium
    elide: Text.ElideRight
}
