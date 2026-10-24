import QtQuick
import QtQuick.Layouts
import stage.modules.common.widgets
import stage.services
import "../clock"
import ".."

/** The latest captures, ready to drag into any app; take a new one or open the folder. */
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
        columnsWanted: 2
        imagesOnly: true
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.files.length === 0
        implicitHeight: 72
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("No screenshots yet")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        ClockButton {
            Layout.fillWidth: true
            variant: "filled"
            symbol: "screenshot_region"
            label: Translation.tr("Take screenshot")
            onClicked: {
                panel.host?.closePanel();
                panel.tile?.takeScreenshot();
            }
        }
        ClockButton {
            Layout.fillWidth: true
            visible: panel.tile?.latest !== null
            symbol: "content_copy"
            label: Translation.tr("Copy latest")
            onClicked: panel.tile?.copyLatest()
        }
        ClockButton {
            Layout.fillWidth: true
            symbol: "folder_open"
            label: Translation.tr("Open folder")
            onClicked: {
                panel.tile?.openFolder();
                panel.host?.closePanel();
            }
        }
    }
}
