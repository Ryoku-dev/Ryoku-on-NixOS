import QtQuick
import QtQuick.Layouts
import stage.modules.common
import stage.modules.common.widgets

/**
 * The heading over a run of rows on Edit Mode's panel.
 */
StyledText {
    Layout.fillWidth: true
    Layout.leftMargin: Appearance.sizes.space2
    Layout.topMargin: Appearance.sizes.space4
    Layout.bottomMargin: Appearance.sizes.space1
    font.family: Appearance.font.family.monospace
    font.pixelSize: Appearance.font.pixelSize.smaller
    font.weight: Font.Medium
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Appearance.font.trackLabel
    color: Appearance.colors.colSubtext
}
