import QtQuick
import Ryoku.Ui.Singletons

// Parent rows into body (parent: details.body).
Item {
    id: details

    property string title: ""
    property bool expanded: false
    readonly property alias body: bodyHost

    signal toggled(bool expanded)

    implicitWidth: 200 * Theme.scale
    implicitHeight: col.implicitHeight

    property real _reveal: details.expanded ? 1 : 0
    Behavior on _reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }

    Column {
        id: col
        width: details.width
        spacing: 6 * Theme.scale

        Item {
            width: parent.width
            height: headerRow.implicitHeight + 8 * Theme.scale

            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * Theme.scale

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: details.expanded ? "\u25be" : (I18n.rtl ? "\u25c2" : "\u25b8")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontSmall
                    color: Theme.withAlpha(Theme.surfaceText, details.expanded ? 0.85 : 0.55)
                    renderType: Text.NativeRendering
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: details.title
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
                    details.expanded = !details.expanded
                    details.toggled(details.expanded)
                }
            }
        }

        Item {
            width: parent.width
            clip: true
            visible: height > 0.5
            height: bodyHost.implicitHeight * details._reveal
            opacity: details._reveal

            Item {
                id: bodyHost
                width: parent.width
                implicitHeight: childrenRect.height
            }
        }
    }
}
