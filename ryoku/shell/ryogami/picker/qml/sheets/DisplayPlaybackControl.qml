import QtQuick
import Ryoku.Ui.Singletons

Row {
    id: root

    property bool manual: false
    property bool paused: false

    signal pauseToggled(bool wantManual)

    spacing: 9 * Theme.scale

    FolioAction {
        anchors.verticalCenter: parent.verticalCenter
        fixedWidth: 132 * Theme.scale
        label: root.manual ? I18n.tr("Resume wallpaper") : I18n.tr("Pause wallpaper")
        active: root.manual
        onTriggered: root.pauseToggled(!root.manual)
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.manual ? I18n.tr("Paused manually")
            : root.paused ? I18n.tr("Paused by another rule")
            : I18n.tr("Playing")
        font.family: Theme.sans
        font.weight: Font.Medium
        font.pixelSize: Theme.fontFine
        color: Theme.withAlpha(Theme.surfaceText, 0.56)
        renderType: Text.NativeRendering
    }
}
