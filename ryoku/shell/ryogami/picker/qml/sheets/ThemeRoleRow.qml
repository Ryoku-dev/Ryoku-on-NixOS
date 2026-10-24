import QtQuick

Item {
    id: row

    property string roleName: ""
    property string roleKey: ""
    property color swatch: "transparent"
    property string hex: ""
    property bool active: false

    signal clicked()

    implicitHeight: 30 * Theme.scale
    implicitWidth: 200 * Theme.scale

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: row.active ? Theme.withAlpha(Theme.surfaceText, 0.09)
             : hover.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.05)
             : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    Text {
        id: hexLabel
        anchors.right: parent.right
        anchors.rightMargin: 7 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        text: row.hex
        font.family: Theme.display
        font.pixelSize: Theme.fontFine
        color: Theme.withAlpha(Theme.surfaceText, 0.46)
        renderType: Text.NativeRendering
    }

    Row {
        id: lead
        anchors.left: parent.left
        anchors.leftMargin: 7 * Theme.scale
        anchors.right: hexLabel.left
        anchors.rightMargin: 8 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * Theme.scale

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 10 * Theme.scale
            height: 10 * Theme.scale
            Rectangle {
                anchors.centerIn: parent
                width: 6 * Theme.scale
                height: 6 * Theme.scale
                radius: width / 2
                color: row.active ? Theme.withAlpha(Theme.surfaceText, 0.9) : "transparent"
                border.width: row.active ? 0 : 1
                border.color: Theme.withAlpha(Theme.surfaceText, 0.4)
                Behavior on color { ColorAnimation { duration: Theme.fast } }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 24 * Theme.scale
            height: 16 * Theme.scale
            color: row.swatch
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.5)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, lead.width - (10 + 24) * Theme.scale - lead.spacing * 2)
            text: row.roleName
            elide: Text.ElideRight
            font.family: Theme.sans
            font.weight: row.active ? Font.DemiBold : Font.Medium
            font.pixelSize: Theme.fontWide
            color: Theme.surfaceText
            renderType: Text.NativeRendering
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
