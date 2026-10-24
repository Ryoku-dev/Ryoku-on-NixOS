import QtQuick
import QtQuick.Layouts
import stage
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import Ryoku.Ui as Ui
import Ryoku.Ui.Singletons

// Both galleries drive Ryoku's real palette owners. Wallpaper cards tune
// matugen.json; named cards set shell.json theme.theme through ryoku-shell.
StyledFlickable {
    id: root

    contentHeight: column.implicitHeight
    clip: true

    ColumnLayout {
        id: column
        width: root.width
        spacing: Tokens.s3

        Ui.SettingCard {
            Layout.fillWidth: true
            title: Translation.tr("WALLPAPER COLOURS")
            collapsible: false

            Ui.SettingRow {
                width: parent.width
                label: Translation.tr("Source colour")
                desc: Translation.tr("Choose which dominant wallpaper colour leads.")
                block: true
                enabled: !MaterialThemeLoader.busy

                Ui.Chips {
                    anchors.fill: parent
                    options: ["0", "1", "2", "3", "4"]
                    labels: ({
                        "0": Translation.tr("1st"),
                        "1": Translation.tr("2nd"),
                        "2": Translation.tr("3rd"),
                        "3": Translation.tr("4th"),
                        "4": Translation.tr("5th")
                    })
                    current: String(MaterialThemeLoader.sourceColorIndex)
                    onChose: key =>
                        MaterialThemeLoader.setSourceColorIndex(Number(key))
                }
            }

            Ui.SettingRow {
                width: parent.width
                divider: true
                label: Translation.tr("Scheme variant")
                desc: Translation.tr("Previewed from the current wallpaper.")
                block: true
                enabled: !MaterialThemeLoader.busy

                ColorPreviewGrid {
                    anchors.fill: parent
                    source: "wallpaper"
                    showTooltips: true
                }
            }
        }

        EditPanelNotice {
            Layout.fillWidth: true
            visible: MaterialThemeLoader.followsWallpaper
            symbol: "wallpaper"
            text: Translation.tr("The selected variant follows the current wallpaper.")
        }

        EditPanelNotice {
            Layout.fillWidth: true
            visible: !MaterialThemeLoader.catalogReady
            symbol: "hourglass_top"
            text: Translation.tr("Loading the theme catalogue…")
        }

        EditPanelNotice {
            Layout.fillWidth: true
            visible: MaterialThemeLoader.catalogReady
                && MaterialThemeLoader.namedThemes.length === 0
            symbol: "info"
            text: Translation.tr("No named themes are available.")
        }

        Ui.SettingCard {
            Layout.fillWidth: true
            visible: MaterialThemeLoader.namedThemes.length > 0
            title: Translation.tr("NAMED THEMES")
            collapsible: false

            Ui.SettingRow {
                width: parent.width
                label: Translation.tr("Installed themes")
                desc: Translation.tr("%1 choices").arg(
                    String(MaterialThemeLoader.namedThemes.length))
                block: true
                enabled: !MaterialThemeLoader.busy

                ColorPreviewGrid {
                    anchors.fill: parent
                    source: "themes"
                    showTooltips: true
                }
            }
        }

        EditPanelNotice {
            Layout.fillWidth: true
            visible: MaterialThemeLoader.lastError !== ""
            symbol: "error"
            text: MaterialThemeLoader.lastError
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: Tokens.s2
        }
    }
}
