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
            placeholderText: Config.options.screenSnip.savePath || (Directories.pictures.replace("file://", "") + "/Screenshots")
            inputText: Config.options.dock.utilities.screenshots.folder
            textField.onEditingFinished: Config.options.dock.utilities.screenshots.folder = textField.text.trim()
        }
        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr("Leave it empty to follow the screen snip save folder.")
        }
    }
}
