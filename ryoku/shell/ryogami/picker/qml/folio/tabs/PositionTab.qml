import QtQuick
import Ryoku.Ui.Singletons

FolioTabData {
    tabKey: "position"
    title: I18n.tr("Position")
    note: I18n.tr("Position each picker style and its search panel independently.")
    sections: [
        {
            title: I18n.tr("Slices"),
            subtitle: "",
            controls: [
                { id: "components.wallpaperSelector.sliceStageX",
                  key: "components.wallpaperSelector.sliceStageX",
                  kind: "number",
                  label: I18n.tr("Horizontal offset"),
                  help: I18n.tr("Move the picker left or right by a percentage of half the screen width. Positive values move it right."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.sliceStageX", "slices", "horizontal", "offset", "position", "number"] },
                { id: "components.wallpaperSelector.sliceStageY",
                  key: "components.wallpaperSelector.sliceStageY",
                  kind: "number",
                  label: I18n.tr("Vertical offset"),
                  help: I18n.tr("Move the picker up or down by a percentage of half the screen height. Positive values move it down."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.sliceStageY", "slices", "vertical", "offset", "position", "number"] }
            ]
        },
        {
            title: I18n.tr("Geometric"),
            subtitle: "",
            controls: [
                { id: "components.wallpaperSelector.hexStageX",
                  key: "components.wallpaperSelector.hexStageX",
                  kind: "number",
                  label: I18n.tr("Horizontal offset"),
                  help: I18n.tr("Move the picker left or right by a percentage of half the screen width. Positive values move it right."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.hexStageX", "geometric", "hex", "horizontal", "offset", "number"] },
                { id: "components.wallpaperSelector.hexStageY",
                  key: "components.wallpaperSelector.hexStageY",
                  kind: "number",
                  label: I18n.tr("Vertical offset"),
                  help: I18n.tr("Move the picker up or down by a percentage of half the screen height. Positive values move it down."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.hexStageY", "geometric", "hex", "vertical", "offset", "number"] }
            ]
        },
        {
            title: I18n.tr("Wall"),
            subtitle: "",
            controls: [
                { id: "components.wallpaperSelector.gridStageX",
                  key: "components.wallpaperSelector.gridStageX",
                  kind: "number",
                  label: I18n.tr("Horizontal offset"),
                  help: I18n.tr("Move the picker left or right by a percentage of half the screen width. Positive values move it right."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.gridStageX", "wall", "grid", "horizontal", "offset", "number"] },
                { id: "components.wallpaperSelector.gridStageY",
                  key: "components.wallpaperSelector.gridStageY",
                  kind: "number",
                  label: I18n.tr("Vertical offset"),
                  help: I18n.tr("Move the picker up or down by a percentage of half the screen height. Positive values move it down."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.gridStageY", "wall", "grid", "vertical", "offset", "number"] }
            ]
        },
        {
            title: I18n.tr("Sandy"),
            subtitle: "",
            controls: [
                { id: "components.wallpaperSelector.sandyStageX",
                  key: "components.wallpaperSelector.sandyStageX",
                  kind: "number",
                  label: I18n.tr("Horizontal offset"),
                  help: I18n.tr("Move the picker left or right by a percentage of half the screen width. Positive values move it right."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.sandyStageX", "sandy", "horizontal", "offset", "number"] },
                { id: "components.wallpaperSelector.sandyStageY",
                  key: "components.wallpaperSelector.sandyStageY",
                  kind: "number",
                  label: I18n.tr("Vertical offset"),
                  help: I18n.tr("Move the picker up or down by a percentage of half the screen height. Positive values move it down."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.sandyStageY", "sandy", "vertical", "offset", "number"] }
            ]
        },
        {
            title: I18n.tr("Card hand"),
            subtitle: "",
            controls: [
                { id: "components.wallpaperSelector.handStageX",
                  key: "components.wallpaperSelector.handStageX",
                  kind: "number",
                  label: I18n.tr("Horizontal offset"),
                  help: I18n.tr("Move the picker left or right by a percentage of half the screen width. Positive values move it right."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.handStageX", "hand", "horizontal", "offset", "number"] },
                { id: "components.wallpaperSelector.handStageY",
                  key: "components.wallpaperSelector.handStageY",
                  kind: "number",
                  label: I18n.tr("Vertical offset"),
                  help: I18n.tr("Move the picker up or down by a percentage of half the screen height. Positive values move it down."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.handStageY", "hand", "vertical", "offset", "number"] }
            ]
        },
        {
            title: I18n.tr("Duel"),
            subtitle: "",
            controls: [
                { id: "components.wallpaperSelector.duelStageX",
                  key: "components.wallpaperSelector.duelStageX",
                  kind: "number",
                  label: I18n.tr("Horizontal offset"),
                  help: I18n.tr("Move the picker left or right by a percentage of half the screen width. Positive values move it right."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.duelStageX", "duel", "horizontal", "offset", "number"] },
                { id: "components.wallpaperSelector.duelStageY",
                  key: "components.wallpaperSelector.duelStageY",
                  kind: "number",
                  label: I18n.tr("Vertical offset"),
                  help: I18n.tr("Move the picker up or down by a percentage of half the screen height. Positive values move it down."),
                  unit: I18n.tr("%"),
                  perMode: true,
                  search: ["components.wallpaperSelector.duelStageY", "duel", "vertical", "offset", "number"] }
            ]
        },
        {
            title: I18n.tr("Search panel"),
            subtitle: "",
            controls: [
                { id: "components.wallpaperSelector.tagCloudOffsetX",
                  key: "components.wallpaperSelector.tagCloudOffsetX",
                  kind: "number",
                  label: I18n.tr("Search panel horizontal offset"),
                  help: I18n.tr("Move the search panel left or right relative to this picker."),
                  unit: I18n.tr("px"),
                  search: ["components.wallpaperSelector.tagCloudOffsetX", "search", "panel", "tag", "cloud", "horizontal", "offset", "number"] },
                { id: "components.wallpaperSelector.tagCloudOffsetY",
                  key: "components.wallpaperSelector.tagCloudOffsetY",
                  kind: "number",
                  label: I18n.tr("Search panel vertical offset"),
                  help: I18n.tr("Move the search panel up or down relative to this picker."),
                  unit: I18n.tr("px"),
                  search: ["components.wallpaperSelector.tagCloudOffsetY", "search", "panel", "tag", "cloud", "vertical", "offset", "number"] }
            ]
        }
    ]
}
