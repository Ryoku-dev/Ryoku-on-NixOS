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
            text: Translation.tr("Resource Fill Cards Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family:    Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Resource Fill Cards Settings")
        icon: "donut_large"

        Item {
            Layout.fillWidth: true
            implicitHeight: 200
            visible: !Config.isWidgetActive("resource_fill_cards")

            PagePlaceholder {
                anchors.fill: parent
                icon:    "donut_large"
                shape:   MaterialShape.Shape.Circle
                title:       Translation.tr("Resource Fill Cards disabled")
                description: Translation.tr("Enable Resource Fill Cards in Desktop Widgets settings to configure options.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: Config.isWidgetActive("resource_fill_cards")

            // ── Orientation ──────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Layout Orientation") }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.resource_fill_cards.orientation ?? "horizontal"
                onSelected: value => Config.options.background.widgets.resource_fill_cards.orientation = value
                options: [
                    { displayName: Translation.tr("Horizontal"), icon: "view_column", value: "horizontal" },
                    { displayName: Translation.tr("Vertical"), icon: "view_stream", value: "vertical" }
                ]
            }

            Item { Layout.preferredHeight: 4 }

            // ── Scale ────────────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Widget Scale") }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Scale")
                value: Config.options.background.widgets.resource_fill_cards.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.resource_fill_cards.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Active Card Toggles ──────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Active Resource Cards") }

            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("CPU Usage Card")
                checked: Config.options.background.widgets.resource_fill_cards.enableCpu ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.resource_fill_cards.enableCpu = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "memory_alt"
                text: Translation.tr("RAM Memory Card")
                checked: Config.options.background.widgets.resource_fill_cards.enableRam ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.resource_fill_cards.enableRam = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "hard_drive"
                text: Translation.tr("Disk Storage Card")
                checked: Config.options.background.widgets.resource_fill_cards.enableDisk ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.resource_fill_cards.enableDisk = checked;
                }
            }
        }
    }
}
