import QtQuick
import Ryoku.Ui.Singletons

FolioTabData {
    tabKey: "language"
    title: I18n.tr("Language")
    note: I18n.tr("Choose the language used by the picker and settings.")
    sections: [
        {
            title: I18n.tr("Interface language"),
            subtitle: "",
            controls: [
                { id: "general.language",
                  key: "general.language",
                  kind: "dropdown",
                  label: I18n.tr("Language"),
                  help: I18n.tr("System default follows your desktop language. Wallpaper names and tags stay as they are."),
                  dynamic: "languages",
                  store: "shell",
                  search: ["general.language", "language", "system", "default", "dropdown", "auto"] }
            ]
        }
    ]
}
