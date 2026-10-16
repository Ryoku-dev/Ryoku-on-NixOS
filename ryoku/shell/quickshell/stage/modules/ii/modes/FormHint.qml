import stage.modules.common
import stage.modules.common.widgets
import stage.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/** Explanatory line under a control in a condition or action form. */
StyledText {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    font.pixelSize: ClockStyle.textSmall
    color: ClockStyle.colSubtext
}
