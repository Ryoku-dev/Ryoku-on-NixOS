import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import stage.services
import stage.modules.common
import stage.modules.common.widgets

GroupButton {
    id: root
    property real maximumLabelWidth: 140
    property string buttonIcon
    property string buttonShape
    property string buttonSymbol
    property string buttonColor
    property bool leftmost: false
    property bool rightmost: false

    horizontalPadding: Appearance.sizes.space3
    verticalPadding: Appearance.sizes.space1
    bounce: false
    clickedWidth: baseWidth
    buttonRadius: Appearance.rounding.small
    buttonRadiusPressed: Appearance.rounding.small
    leftRadius: Appearance.rounding.small
    rightRadius: Appearance.rounding.small
    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitHeight: Appearance.sizes.controlHeight
    scale: root.isPressed ? 0.96 : 1

    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondary
    colBackgroundToggledHover: Appearance.colors.colSecondaryHover
    colBackgroundToggledActive: Appearance.colors.colSecondaryActive

    readonly property color contentColor: root.toggled
        ? Appearance.colors.colOnSecondary
        : (root.isHovered ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant)

    background: Rectangle {
        radius: Appearance.rounding.small
        color: root.color
        border.width: root.activeFocus ? 2 : 1
        border.color: root.toggled ? Appearance.colors.colSecondary
            : root.activeFocus ? Appearance.colors.colOnSurface
            : root.isHovered ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant
        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
    }

    contentItem: RowLayout {
        spacing: label.visible && (icon.visible || shapeLoader.visible || symbolLoader.visible)
            ? Appearance.sizes.space1 : 0

        MaterialSymbol {
            id: icon
            Layout.alignment: Qt.AlignVCenter
            visible: root.buttonIcon !== undefined && root.buttonIcon !== ""
            text: root.buttonIcon || ""
            iconSize: 18
            fill: root.toggled ? 1 : 0
            color: root.contentColor
        }

        Loader {
            id: shapeLoader
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonShape !== undefined && root.buttonShape !== ""
            visible: active
            sourceComponent: root.buttonShape === "Rectangle" ? rectangleShapeComp : materialShapeComp
        }

        Component {
            id: rectangleShapeComp
            Rectangle {
                implicitWidth: 18
                implicitHeight: 18
                radius: Appearance.rounding.small
                color: root.buttonColor !== "" ? root.buttonColor : root.contentColor
            }
        }

        Component {
            id: materialShapeComp
            MaterialShape {
                implicitWidth: 18
                implicitHeight: 18
                shapeString: root.buttonShape
                color: root.buttonColor !== "" ? root.buttonColor : root.contentColor
            }
        }

        Loader {
            id: symbolLoader
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonSymbol !== undefined && root.buttonSymbol !== ""
            visible: active
            sourceComponent: CustomIcon {
                width: 18
                height: 18
                source: root.buttonSymbol
                colorize: true
                color: root.contentColor
            }
        }

        StyledText {
            id: label
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: 0
            Layout.maximumWidth: root.maximumLabelWidth
            visible: root.buttonText !== undefined && root.buttonText.length > 0
            color: root.contentColor
            text: root.buttonText || ""
            elide: Text.ElideRight
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
        }
    }
}
