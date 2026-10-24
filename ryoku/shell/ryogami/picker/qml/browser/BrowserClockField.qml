import QtQuick

// Sits on the dark photo backdrop, so it wears the modal's white-on-glass look.
Rectangle {
    id: clock

    property alias text: input.text
    property string placeholder: "0:00"

    signal edited(string value)

    implicitWidth: 62 * Theme.scale
    implicitHeight: input.implicitHeight + 8 * Theme.scale
    color: Qt.rgba(1, 1, 1, 0.1)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.22)

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 6 * Theme.scale
        anchors.rightMargin: 6 * Theme.scale
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        font.family: Theme.display
        font.pixelSize: Theme.fontBody
        color: "white"
        selectionColor: Qt.rgba(1, 1, 1, 0.24)
        selectedTextColor: "white"
        selectByMouse: true
        renderType: Text.NativeRendering
        onTextEdited: clock.edited(text)

        Text {
            anchors.fill: parent
            visible: input.text.length === 0
            verticalAlignment: Text.AlignVCenter
            text: clock.placeholder
            font: input.font
            color: Qt.rgba(1, 1, 1, 0.4)
            renderType: Text.NativeRendering
        }
    }
}
