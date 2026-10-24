import QtQuick

// A row in a masthead dropdown. The chosen row carries a bone tick at its edge; a row that
// cannot run yet dims and says why on the right.
Item {
    id: row

    property string glyph: ""
    property string label: ""
    property string detail: ""
    property bool selected: false
    property bool available: true

    signal chosen()

    readonly property bool hovered: mouse.containsMouse

    width: parent ? parent.width : implicitWidth
    implicitHeight: 30 * Theme.scale

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.withAlpha(Theme.surfaceText, row.hovered ? 0.08 : row.selected ? 0.05 : 0)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2 * Theme.scale
        height: row.selected ? parent.height - 12 * Theme.scale : 0
        radius: width
        color: Theme.surfaceText
        Behavior on height { NumberAnimation { duration: Theme.standard; easing.type: Easing.OutBack } }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10 * Theme.scale
        opacity: row.available ? 1 : 0.45
        transform: Translate {
            x: row.hovered ? 3 * Theme.scale : 0
            Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        }

        Text {
            visible: row.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * Theme.scale
            horizontalAlignment: Text.AlignHCenter
            text: row.glyph
            font.family: Theme.icon
            font.pixelSize: Theme.fs(13.5)
            color: Theme.withAlpha(Theme.surfaceText, row.selected || row.hovered ? 1 : 0.62)
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, row.width - 56 * Theme.scale - detailText.implicitWidth)
            elide: Text.ElideMiddle
            text: row.label
            font.family: Theme.sans
            font.weight: row.selected ? Font.DemiBold : Font.Normal
            font.pixelSize: Theme.fs(12.5)
            color: row.selected || row.hovered ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.8)
            renderType: Text.NativeRendering
        }
    }
    Text {
        id: detailText
        visible: row.detail.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 10 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        text: row.detail
        font.family: Theme.sans
        font.pixelSize: Theme.fs(10.5)
        color: Theme.withAlpha(Theme.surfaceText, 0.5)
        renderType: Text.NativeRendering
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.chosen()
    }
}
