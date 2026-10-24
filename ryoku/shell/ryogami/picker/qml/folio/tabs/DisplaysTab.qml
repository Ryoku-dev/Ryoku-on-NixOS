import QtQuick
import Ryoku.Ui.Singletons

FolioTabData {
    tabKey: "displays"
    title: I18n.tr("Wallpapers and displays")
    note: I18n.tr("See what each display is showing, change its placement, or protect it from updates.")
    sections: [
        {
            title: I18n.tr("Wallpapers and displays"),
            subtitle: I18n.tr("These are the wallpapers currently reported by the wallpaper service. Changes made here apply to one display at a time."),
            controls: [
                { id: "display.fillModes.<output>",
                  key: "display.fillModes.<output>",
                  kind: "chips",
                  label: I18n.tr("Placement"),
                  help: "",
                  options: [{ value: "fill", label: I18n.tr("Fill") }, { value: "fit", label: I18n.tr("Fit") }, { value: "stretch", label: I18n.tr("Stretch") }, { value: "center", label: I18n.tr("Center") }, { value: "tile", label: I18n.tr("Tile") }, { value: "span", label: I18n.tr("Span") }],
                  perDisplay: true },
                { id: "display.outputLocks.<output>",
                  key: "display.outputLocks.<output>",
                  kind: "toggle",
                  label: I18n.tr("Lock"),
                  help: "",
                  perDisplay: true },
                { id: "display.themeOutput.<output>",
                  key: null,
                  kind: "display",
                  label: I18n.tr("Colours"),
                  help: "",
                  perDisplay: true },
                { id: "audio.<output>",
                  key: null,
                  kind: "display",
                  label: I18n.tr("Audio"),
                  help: "",
                  perDisplay: true },
                { id: "playback.<output>",
                  key: null,
                  kind: "display",
                  label: I18n.tr("Playback"),
                  help: "",
                  perDisplay: true }
            ]
        }
    ]
}
