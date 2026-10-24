import QtQuick

// A section heading: accent tick, spaced caps, and a hairline running to the edge.
Item {
    id: label

    property string text: ""

    implicitHeight: Math.max(caption.implicitHeight, 14 * Theme.scale)

    Rectangle {
        id: tick
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2 * Theme.scale
        height: caption.implicitHeight
        color: Theme.withAlpha(Theme.surfaceText, 0.85)
    }
    Text {
        id: caption
        anchors.left: tick.right
        anchors.leftMargin: 8 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        text: label.text.toUpperCase()
        font.family: Theme.sans
        font.weight: Font.DemiBold
        font.pixelSize: Theme.fontFine
        font.letterSpacing: 1.6
        color: Theme.withAlpha(Theme.surfaceText, 0.78)
        renderType: Text.NativeRendering
    }
    FolioRule {
        anchors.left: caption.right
        anchors.leftMargin: 12 * Theme.scale
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        alpha: 0.4
    }
}
