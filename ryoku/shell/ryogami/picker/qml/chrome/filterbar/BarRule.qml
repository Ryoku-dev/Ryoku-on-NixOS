import QtQuick

// A short vertical hairline between groups of masthead controls.
Item {
    width: 17 * Theme.scale
    height: 30 * Theme.scale

    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: 16 * Theme.scale
        color: Theme.withAlpha(Theme.surfaceText, 0.18)
    }
}
