import QtQuick
import QtQuick.Layouts
import stage.services
import "."
import ".."

UtilityConfigPage {
    title: Translation.tr("Screenshots")

    ContentSection {
        title: Translation.tr("Folder")
        icon: "screenshot_region"
        tooltip: Translation.tr("Where the widget looks for captures")

        ConfigTextField {
            icon: "folder_open"
            text: Translation.tr("Folder path")
            placeholderText: FileUtils.trimFileProtocol(Directories.pictures) + "/Screenshots"
            inputText: Config.options.dock.utilities.screenshots.folder
            textField.onEditingFinished: Config.options.dock.utilities.screenshots.folder = textField.text.trim()
        }
        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr("Leave it empty to follow the folder selected in Ryoku's screenshot tool.")
        }
    }
}
