import QtQuick

// A true binary. On flips the track to a bone plate and slides the knob across; off is a
// hairline track with a muted knob. The knob springs as it lands, the one bit of motion.
Item {
    id: sw

    property bool checked: false

    signal toggled(bool checked)

    implicitWidth: 44 * Theme.scale
    implicitHeight: 24 * Theme.scale

    readonly property bool hovered: area.containsMouse
    readonly property real _pad: 3 * Theme.scale
    readonly property real _knob: height - sw._pad * 2

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Theme.withAlpha(Theme.surfaceText, sw.enabled ? 1 : 0.4)
             : sw.hovered && sw.enabled ? Theme.withAlpha(Theme.surfaceText, 0.12)
             : Theme.withAlpha(Theme.surfaceText, 0.05)
        border.width: 1
        border.color: sw.checked ? "transparent"
             : Theme.withAlpha(Theme.surfaceText, sw.enabled ? 0.3 : 0.16)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    Rectangle {
        id: knob
        width: sw._knob
        height: sw._knob
        radius: sw._knob / 2
        y: sw._pad
        x: sw.checked ? sw.width - width - sw._pad : sw._pad
        color: sw.checked ? Theme.surface
             : Theme.withAlpha(Theme.surfaceText, sw.enabled ? 0.7 : 0.35)
        Behavior on x { NumberAnimation { duration: Theme.standard; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: sw.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}
