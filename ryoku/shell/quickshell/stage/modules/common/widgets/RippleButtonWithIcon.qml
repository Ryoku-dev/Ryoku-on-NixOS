import QtQuick
import QtQuick.Layouts
import stage.modules.common
import stage.modules.common.widgets

RippleButton {
    id: buttonWithIconRoot
    property string nerdIcon
    property string materialIcon
    property string hoverMaterialIcon: ""
    property bool hoverIconSuppressed: false
    property bool materialIconFill: true
    property bool iconOnRight: false
    property bool centerContent: false
    property real iconPixelSize: Appearance.font.pixelSize.larger
    property int textPixelSize: Appearance.font.pixelSize.small
    property int mainTextWeight: Font.DemiBold
    property string mainTextFontFamily: Appearance.font.family.main
    property var mainTextVariableAxes: Appearance.font.variableAxes.main
    property real contentSpacing: Appearance.rounding.verysmall
    property string mainText: "Button text"
    readonly property real contentImplicitWidth: contentItem ? contentItem.implicitWidth : 0
    readonly property real contentImplicitHeight: contentItem ? contentItem.implicitHeight : 0
    property color colText: Appearance.colors.colOnSecondaryContainer
    property Component mainContentComponent: Component {
        StyledText {
            visible: text !== ""
            text: buttonWithIconRoot.mainText
            font.family: buttonWithIconRoot.mainTextFontFamily
            font.variableAxes: buttonWithIconRoot.mainTextVariableAxes
            font.pixelSize: buttonWithIconRoot.textPixelSize
            font.weight: buttonWithIconRoot.mainTextWeight
            color: buttonWithIconRoot.colText
        }
    }
    implicitHeight: 35
    horizontalPadding: 10
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        RowLayout {
            id: contentRow
            anchors.centerIn: buttonWithIconRoot.centerContent ? parent : undefined
            anchors.left: buttonWithIconRoot.centerContent ? undefined : parent.left
            anchors.right: buttonWithIconRoot.centerContent ? undefined : parent.right
            anchors.verticalCenter: buttonWithIconRoot.centerContent ? undefined : parent.verticalCenter
            spacing: buttonWithIconRoot.mainText !== "" ? 8 : 0
            Item {
                visible: !buttonWithIconRoot.iconOnRight
                Layout.fillWidth: !buttonWithIconRoot.iconOnRight && buttonWithIconRoot.mainText === ""
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.alignment: Qt.AlignCenter
                implicitWidth: Math.max(materialIconLoader.implicitWidth, nerdIconLoader.implicitWidth)
                implicitHeight: Math.max(materialIconLoader.implicitHeight, nerdIconLoader.implicitHeight)
                Loader {
                    id: materialIconLoader
                    anchors.centerIn: parent
                    active: !buttonWithIconRoot.nerdIcon
                    sourceComponent: MaterialSymbol {
                        text: buttonWithIconRoot.materialIcon
                        iconSize: buttonWithIconRoot.iconPixelSize
                        color: buttonWithIconRoot.colText
                        fill: buttonWithIconRoot.materialIconFill ? 1 : 0
                    }
                }
                Loader {
                    id: nerdIconLoader
                    anchors.centerIn: parent
                    active: !!buttonWithIconRoot.nerdIcon
                    sourceComponent: StyledText {
                        text: buttonWithIconRoot.nerdIcon
                        font.pixelSize: buttonWithIconRoot.iconPixelSize
                        font.family: Appearance.font.family.iconNerd
                        color: buttonWithIconRoot.colText
                    }
                }
            }
            Loader {
                id: mainTextLoader
                visible: buttonWithIconRoot.mainText !== ""
                Layout.fillWidth: !buttonWithIconRoot.centerContent && buttonWithIconRoot.mainText !== ""
                Layout.preferredWidth: item ? item.implicitWidth : 0
                Layout.preferredHeight: item ? item.implicitHeight : 0
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: buttonWithIconRoot.mainContentComponent
            }
            Item {
                visible: buttonWithIconRoot.iconOnRight
                Layout.fillWidth: buttonWithIconRoot.iconOnRight && buttonWithIconRoot.mainText === ""
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.alignment: Qt.AlignCenter
                readonly property bool animatedIconEnabled: buttonWithIconRoot.hoverMaterialIcon !== ""
                    && !buttonWithIconRoot.nerdIcon
                readonly property bool hoverIconActive: animatedIconEnabled
                    && !buttonWithIconRoot.hoverIconSuppressed
                    && (buttonWithIconRoot.hovered || buttonWithIconRoot.down)
                implicitWidth: Math.max(
                    trailingMaterialIconLoader.implicitWidth,
                    trailingNerdIconLoader.implicitWidth,
                    trailingBaseAnimatedIcon.implicitWidth,
                    trailingHoverAnimatedIcon.implicitWidth)
                implicitHeight: Math.max(
                    trailingMaterialIconLoader.implicitHeight,
                    trailingNerdIconLoader.implicitHeight,
                    trailingBaseAnimatedIcon.implicitHeight,
                    trailingHoverAnimatedIcon.implicitHeight)
                clip: animatedIconEnabled
                Loader {
                    id: trailingMaterialIconLoader
                    anchors.centerIn: parent
                    active: !buttonWithIconRoot.nerdIcon && !parent.animatedIconEnabled
                    sourceComponent: MaterialSymbol {
                        text: buttonWithIconRoot.materialIcon
                        iconSize: buttonWithIconRoot.iconPixelSize
                        color: buttonWithIconRoot.colText
                        fill: buttonWithIconRoot.materialIconFill ? 1 : 0
                    }
                }
                Loader {
                    id: trailingBaseAnimatedIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: parent.animatedIconEnabled
                    y: parent.hoverIconActive ? -height : 0
                    sourceComponent: MaterialSymbol {
                        text: buttonWithIconRoot.materialIcon
                        iconSize: buttonWithIconRoot.iconPixelSize
                        color: buttonWithIconRoot.colText
                        fill: buttonWithIconRoot.materialIconFill ? 1 : 0
                    }

                    Behavior on y {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
                Loader {
                    id: trailingHoverAnimatedIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: parent.animatedIconEnabled
                    y: parent.hoverIconActive ? 0 : height
                    sourceComponent: MaterialSymbol {
                        text: buttonWithIconRoot.hoverMaterialIcon
                        iconSize: buttonWithIconRoot.iconPixelSize
                        color: buttonWithIconRoot.colText
                        fill: buttonWithIconRoot.materialIconFill ? 1 : 0
                    }

                    Behavior on y {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
                Loader {
                    id: trailingNerdIconLoader
                    anchors.centerIn: parent
                    active: !!buttonWithIconRoot.nerdIcon
                    sourceComponent: StyledText {
                        text: buttonWithIconRoot.nerdIcon
                        font.pixelSize: buttonWithIconRoot.iconPixelSize
                        font.family: Appearance.font.family.iconNerd
                        color: buttonWithIconRoot.colText
                    }
                }
            }
        }
    }
}
