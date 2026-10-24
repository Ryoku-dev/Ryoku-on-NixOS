import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: stack

    property string title: ""
    property bool expanded: false
    readonly property alias body: bodyHost

    signal toggled(bool expanded)

    implicitWidth: 200 * Theme.scale
    implicitHeight: col.implicitHeight

    property real _reveal: stack.expanded ? 1 : 0
    Behavior on _reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }

    Rectangle {
        width: 2
        height: parent.height
        x: I18n.rtl ? parent.width - width : 0
        color: Theme.withAlpha(Theme.surfaceText, stack.expanded ? 0.9 : 0.24)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    Column {
        id: col
        width: stack.width
        spacing: 6 * Theme.scale
        leftPadding: 12 * Theme.scale

        Item {
            width: parent.width - parent.leftPadding
            height: headerRow.implicitHeight + 8 * Theme.scale

            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * Theme.scale

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stack.expanded ? "\u25be" : (I18n.rtl ? "\u25c2" : "\u25b8")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontSmall
                    color: Theme.withAlpha(Theme.surfaceText, stack.expanded ? 0.85 : 0.55)
                    renderType: Text.NativeRendering
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stack.title
                    font.family: Theme.sans
                    font.weight: Font.DemiBold
                    font.pixelSize: Theme.fontBody2
                    color: Theme.surfaceText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    stack.expanded = !stack.expanded
                    stack.toggled(stack.expanded)
                }
            }
        }

        Item {
            width: parent.width - parent.leftPadding
            clip: true
            visible: height > 0.5
            height: bodyHost.implicitHeight * stack._reveal
            opacity: stack._reveal

            Item {
                id: bodyHost
                width: parent.width
                implicitHeight: childrenRect.height
            }
        }
    }
}
