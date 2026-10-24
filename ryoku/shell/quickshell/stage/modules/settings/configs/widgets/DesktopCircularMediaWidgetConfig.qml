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
            text: Translation.tr("Circular Media Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Circular Media Settings")
        icon: "album"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("circular_media")

            PagePlaceholder {
                anchors.fill: parent
                icon: "album"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Circular Media disabled")
                description: Translation.tr("Enable the Circular Media widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("circular_media")

            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: Config.options.background.widgets.circular_media.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.circular_media.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Colors")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Use album colors")
                checked: Config.options.background.widgets.circular_media.useAlbumColors ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.useAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Buttons")
            }

            ConfigSwitch {
                buttonIcon: "skip_previous"
                text: Translation.tr("Show Previous Button")
                checked: Config.options.background.widgets.circular_media.showPrevButton ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.showPrevButton = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "skip_next"
                text: Translation.tr("Show Next Button")
                checked: Config.options.background.widgets.circular_media.showNextButton ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.showNextButton = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Show Audio Device Pill")
                checked: Config.options.background.widgets.circular_media.showDevicePill ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.showDevicePill = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable Glass Reflection")
                checked: Config.options.background.widgets.circular_media.enableGlassReflection ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.enableGlassReflection = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.circular_media.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.circular_media.enableShadows = checked;
                }
            }
        }
    }
}
