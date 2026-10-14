import QtQuick
import QtQuick.Layouts
import Quickshell
import stage.modules.common.widgets
import stage.services
import "../clock"
import ".."

/** The newest files of the folder as a grid; click opens, drag hands a file over. */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var files: panel.tile?.feed?.recent ?? []

    spacing: 8

    FileGrid {
        Layout.fillWidth: true
        visible: panel.files.length > 0
        files: panel.files
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.files.length === 0
        implicitHeight: 72
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("Nothing here yet")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
        }
    }

    ClockButton {
        Layout.fillWidth: true
        symbol: "folder_open"
        label: Translation.tr("Open folder")
        onClicked: {
            Quickshell.execDetached(["xdg-open", panel.tile?.folder ?? ""]);
            panel.host?.closePanel();
        }
    }
}
