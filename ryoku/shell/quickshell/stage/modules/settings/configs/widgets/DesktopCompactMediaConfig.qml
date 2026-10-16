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
            text: Translation.tr("Compact Media Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Compact Media Settings")
        icon: "queue_music"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("compact_media")

            PagePlaceholder {
                anchors.fill: parent
                icon: "queue_music"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Compact Media disabled")
                description: Translation.tr("Enable the Compact Media widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("compact_media")

            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: Config.options.background.widgets.compact_media.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.compact_media.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Colors")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Dynamic album colors")
                checked: Config.options.background.widgets.compact_media.dynamicAlbumColors ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.compact_media.dynamicAlbumColors = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.compact_media.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.compact_media.enableShadows = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable Inner Shadows")
                checked: Config.options.background.widgets.compact_media.enableInnerShadow ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.compact_media.enableInnerShadow = checked;
                }
            }
        }
    }
}
