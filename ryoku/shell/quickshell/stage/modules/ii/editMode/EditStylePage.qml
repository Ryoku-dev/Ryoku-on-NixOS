import QtQuick
import QtQuick.Layouts
import stage
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import Ryoku.Ui as Ui
import Ryoku.Ui.Singletons

StyledFlickable {
    id: root

    contentHeight: column.implicitHeight
    clip: true

    signal openPageRequested(string page)
    signal fieldFocusRequested(Item field)
    signal fieldFocusReleased()

    function schemeName(value) {
        const name = String(value).replace(/^scheme-/, "").replace(/-/g, " ");
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    readonly property string colourSummary: MaterialThemeLoader.followsWallpaper
        ? root.schemeName(MaterialThemeLoader.schemeType)
            + " · " + Translation.tr("source %1")
                .arg(String(MaterialThemeLoader.sourceColorIndex + 1))
        : MaterialThemeLoader.themeName

    ColumnLayout {
        id: column
        width: root.width
        spacing: Tokens.s3

        EditStylePresets {
            Layout.fillWidth: true
            onFieldFocusRequested: field => root.fieldFocusRequested(field)
            onFieldFocusReleased: root.fieldFocusReleased()
        }

        Ui.SettingCard {
            Layout.fillWidth: true
            title: Translation.tr("PALETTE")
            collapsible: false

            Ui.SettingRow {
                width: parent.width
                label: Translation.tr("Light and dark")
                desc: !MaterialThemeLoader.followsWallpaper
                    ? Translation.tr("Choosing a mode returns to wallpaper colours.")
                    : Translation.tr("Auto follows the wallpaper; Sun follows the day.")
                block: true
                enabled: !MaterialThemeLoader.busy

                Ui.Chips {
                    anchors.fill: parent
                    options: ["smart", "sun", "light", "dark"]
                    labels: ({
                        smart: Translation.tr("Auto"),
                        sun: Translation.tr("Sun"),
                        light: Translation.tr("Light"),
                        dark: Translation.tr("Dark")
                    })
                    current: MaterialThemeLoader.mode
                    onChose: key => MaterialThemeLoader.setMode(key)
                }
            }

            Ui.SettingRow {
                width: parent.width
                divider: true
                label: Translation.tr("Colour scheme")
                desc: root.colourSummary
                controlWidth: chooseButton.implicitWidth
                enabled: !MaterialThemeLoader.busy

                Ui.Btn {
                    id: chooseButton
                    anchors.fill: parent
                    text: Translation.tr("Choose")
                    compact: true
                    onAct: root.openPageRequested("colours")
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
