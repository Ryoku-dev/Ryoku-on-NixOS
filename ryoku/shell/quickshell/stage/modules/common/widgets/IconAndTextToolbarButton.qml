import QtQuick
import QtQuick.Layouts
import stage.modules.common

ToolbarButton {
    id: iconBtn
    required property string iconText
    property bool compact: false
    property real maximumLabelWidth: 140
    property color colText: toggled
        ? Appearance.colors.colOnSecondary
        : (hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant)

    Layout.fillHeight: false
    implicitHeight: Appearance.sizes.controlHeight
    implicitWidth: Math.max(implicitHeight,
        contentRow.implicitWidth + horizontalPadding * 2)
    horizontalPadding: Appearance.sizes.space3
    buttonRadius: Appearance.rounding.small
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondary
    colBackgroundToggledHover: Appearance.colors.colSecondaryHover
    colBackgroundToggledActive: Appearance.colors.colSecondaryActive
    colRipple: Appearance.colors.colLayer1Active
    colRippleToggled: Appearance.colors.colOnSecondaryContainer
    borderWidth: activeFocus ? 2 : 1
    borderColor: toggled ? Appearance.colors.colSecondary
        : activeFocus ? Appearance.colors.colOnSurface
        : hovered ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant

    contentItem: Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: label.visible && icon.visible ? Appearance.sizes.space1 : 0

        MaterialSymbol {
            id: icon
            visible: iconBtn.iconText.length > 0
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: 18
            text: iconBtn.iconText
            color: iconBtn.colText
        }
        StyledText {
            id: label
            visible: !iconBtn.compact && iconBtn.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, iconBtn.maximumLabelWidth)
            color: iconBtn.colText
            text: iconBtn.text
            elide: Text.ElideRight
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
        }
    }
}
