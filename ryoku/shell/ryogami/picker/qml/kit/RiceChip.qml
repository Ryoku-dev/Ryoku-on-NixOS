import QtQuick

Rectangle {
    id: chip

    property string label: ""
    property color tint: Theme.withAlpha(Theme.surfaceText, 0.7)
    property bool strong: false

    implicitWidth: chipText.implicitWidth + 16 * Theme.scale
    height: 20 * Theme.scale
    color: chip.strong ? Theme.withAlpha(chip.tint, 0.16) : "transparent"
    border.width: 1
    border.color: Theme.withAlpha(chip.tint, chip.strong ? 0.55 : 0.3)

    Text {
        id: chipText
        anchors.centerIn: parent
        text: chip.label
        font.family: Theme.sans
        font.weight: Font.Medium
        font.pixelSize: Theme.fontFine
        font.letterSpacing: 0.8
        color: chip.strong ? chip.tint : Theme.withAlpha(Theme.surfaceText, 0.7)
        renderType: Text.NativeRendering
    }
}
