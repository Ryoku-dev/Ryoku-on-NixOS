import QtQuick
import QtQuick.Layouts
import stage.modules.common

ToolbarButton {
    id: iconBtn
    Layout.fillHeight: false
    implicitWidth: Appearance.sizes.controlHeight
    implicitHeight: Appearance.sizes.controlHeight
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

    property color colText: toggled
        ? Appearance.colors.colOnSecondary
        : (hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant)
    property bool iconFill: toggled
    property real iconSize: 18

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        iconSize: iconBtn.iconSize
        text: iconBtn.text
        fill: iconBtn.iconFill ? 1 : 0
        color: iconBtn.colText
        animateChange: true
    }
}
