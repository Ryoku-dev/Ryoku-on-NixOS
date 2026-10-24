import QtQuick

Rectangle {
    id: shell

    property string title: ""
    property string note: ""
    property real bodySpacing: 17
    property real reveal: 1
    readonly property alias body: bodyHost

    color: Theme.withAlpha(Theme.background, 0.90)
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.46)

    Column {
        id: col
        anchors.fill: parent
        anchors.topMargin: 25 * Theme.scale
        anchors.rightMargin: 20 * Theme.scale
        anchors.bottomMargin: 20 * Theme.scale
        anchors.leftMargin: 22 * Theme.scale
        spacing: shell.bodySpacing * Theme.scale

        Column {
            width: parent.width
            spacing: 7 * Theme.scale

            Text {
                width: parent.width
                text: shell.title
                font.family: Theme.display
                font.pixelSize: Theme.fontTitle
                color: Theme.surfaceText
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: shell.note.length > 0
                text: shell.note
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontBase
                color: Theme.withAlpha(Theme.surfaceText, 0.56)
                lineHeight: 1.4
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
        }

        Item {
            id: bodyHost
            width: parent.width
            implicitHeight: childrenRect.height
            height: col.height - col.spacing - y
        }
    }
}
