import QtQuick

Item {
    id: field

    property string number: ""
    property string title: ""
    property string desc: ""
    property real reveal: 1
    readonly property alias body: bodyHost

    implicitWidth: 200 * Theme.scale
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: field.width
        spacing: 9 * Theme.scale
        leftPadding: 8 * Theme.scale
        rightPadding: 8 * Theme.scale
        bottomPadding: 6 * Theme.scale

        FolioRule {
            width: parent.width - parent.leftPadding - parent.rightPadding
            alpha: 0.5
            reveal: field.reveal
        }

        Row {
            spacing: 8 * Theme.scale

            Text {
                anchors.baseline: titleText.baseline
                visible: field.number.length > 0
                text: field.number
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.5 * field.reveal)
                renderType: Text.NativeRendering
            }
            Text {
                id: titleText
                text: field.title
                font.family: Theme.sans
                font.weight: Font.DemiBold
                font.pixelSize: Theme.fontLabel
                color: Theme.withAlpha(Theme.surfaceText, field.reveal)
                renderType: Text.NativeRendering
            }
        }

        Text {
            width: parent.width - parent.leftPadding - parent.rightPadding
            visible: field.desc.length > 0
            text: field.desc
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontBase
            color: Theme.withAlpha(Theme.surfaceText, 0.48 * field.reveal)
            lineHeight: 1.35
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        Item {
            id: bodyHost
            width: parent.width - parent.leftPadding - parent.rightPadding
            implicitHeight: childrenRect.height
            height: childrenRect.height
        }
    }
}
