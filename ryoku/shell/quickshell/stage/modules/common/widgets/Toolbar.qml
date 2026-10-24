import QtQuick
import QtQuick.Layouts
import stage.modules.common
import stage.modules.common.widgets

// The Stage toolbar is a compact Ryoku instrument strip: flat paper, a
// hairline edge and one shared corner.
Item {
    id: root

    property bool enableShadow: false
    property real padding: Appearance.sizes.space2
    property alias colBackground: background.color
    property alias spacing: toolbarLayout.spacing
    default property alias toolbarData: toolbarLayout.data
    implicitWidth: background.implicitWidth
    implicitHeight: background.implicitHeight
    width: implicitWidth
    height: implicitHeight
    property alias radius: background.radius

    Loader {
        active: root.enableShadow
        anchors.fill: background
        sourceComponent: StyledRectangularShadow {
            target: background
            anchors.fill: undefined
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        implicitHeight: Appearance.sizes.toolbarHeight
        implicitWidth: toolbarLayout.implicitWidth + root.padding * 2
        radius: Appearance.rounding.small
        border.width: 1
        border.color: Appearance.colors.colOutline

        RowLayout {
            id: toolbarLayout
            spacing: Appearance.sizes.space2
            anchors {
                fill: parent
                margins: root.padding
            }
        }
    }
}
