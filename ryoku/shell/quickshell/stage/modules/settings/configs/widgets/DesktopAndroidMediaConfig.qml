import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Android Media Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Android Media Settings")
        icon: "play_circle"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("media_android")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Android Media disabled")
                description: Translation.tr("Enable the Android Media widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("media_android")

            ContentSubsectionLabel {
                text: Translation.tr("Content")
            }

            ConfigSwitch {
                buttonIcon: "lyrics"
                text: Translation.tr("Show synced lyrics")
                checked: Config.options.background.widgets.media.showLyrics ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media.showLyrics = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "skip_next"
                text: Translation.tr("Show playback controls")
                checked: Config.options.background.widgets.media.showControls ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media.showControls = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Show audio device pill")
                checked: Config.options.background.widgets.media.showDevicePill ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media.showDevicePill = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Appearance")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Dynamic album colors")
                checked: Config.options.background.widgets.media.dynamicAlbumColors ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.media.dynamicAlbumColors = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable shadows")
                checked: Config.options.background.widgets.media.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.media.enableShadows = checked;
                }
            }
        }
    }
}
