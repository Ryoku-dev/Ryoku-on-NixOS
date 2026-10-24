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
            topLeftRadius:    Appearance.rounding.full
            topRightRadius:   Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius:Appearance.rounding.full
            colBackground:      Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple:          Appearance.colors.colSecondaryContainerActive
            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Disk Resource Pill Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family:    Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Disk Pill Settings")
        icon: "hard_drive"

        Item {
            Layout.fillWidth: true
            implicitHeight: 200
            visible: !Config.isWidgetActive("resource_disk_pill")

            PagePlaceholder {
                anchors.fill: parent
                icon:    "hard_drive"
                shape:   MaterialShape.Shape.Circle
                title:       Translation.tr("Disk Resource Pill disabled")
                description: Translation.tr("Enable Disk Resource Pill in Desktop Widgets settings to configure options.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: Config.isWidgetActive("resource_disk_pill")

            // ── Widget Grid Size / Aspect Ratio Selection ───────────────────
            ContentSubsectionLabel { text: Translation.tr("Widget Grid Size & Aspect Ratio") }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.resource_disk_pill.aspectRatio ?? "2x0.5"
                onSelected: value => Config.options.background.widgets.resource_disk_pill.aspectRatio = value
                options: [
                    { displayName: Translation.tr("1x0.5 (Compact Pill)"), icon: "crop_landscape", value: "1x0.5" },
                    { displayName: Translation.tr("2x0.5 (Standard Pill)"), icon: "crop_16_9", value: "2x0.5" }
                ]
            }

            Item { Layout.preferredHeight: 4 }

            // ── Widget Scale Slider ──────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Scale & Size") }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Scale")
                value: Config.options.background.widgets.resource_disk_pill.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.resource_disk_pill.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Details Switch ───────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Details") }

            ConfigSwitch {
                buttonIcon: "info"
                text: Translation.tr("Show GB Used / Total")
                checked: Config.options.background.widgets.resource_disk_pill.showDetails ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.resource_disk_pill.showDetails = checked;
                }
            }
        }
    }
}
