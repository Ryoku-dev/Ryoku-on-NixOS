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
            text: Translation.tr("Circle Pointer Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family:    Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("circle_pointer_clock")

            PagePlaceholder {
                anchors.fill: parent
                icon:    "schedule"
                shape:   MaterialShape.Shape.Circle
                title:       Translation.tr("Circle Pointer Clock disabled")
                description: Translation.tr("Enable the Circle Pointer Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("circle_pointer_clock")

            // ── Size ─────────────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Size") }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text:  Translation.tr("Widget Size")
                value: Config.options.background.widgets.circle_pointer_clock.widgetSize ?? 100
                from: 50; to: 200; stepSize: 10
                onValueChanged: Config.options.background.widgets.circle_pointer_clock.widgetSize = value
            }

            // ── Display Toggles ───────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Display Elements") }

            ConfigSwitch {
                buttonIcon: "tag"
                text:    Translation.tr("Minute Step Numbers")
                checked: Config.options.background.widgets.circle_pointer_clock.showDots ?? true
                onCheckedChanged: Config.options.background.widgets.circle_pointer_clock.showDots = checked
            }

            // ── Style ─────────────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Style & Appearance") }

            ConfigSwitch {
                buttonIcon: "format_bold"
                text:    Translation.tr("Bold Font")
                checked: Config.options.background.widgets.circle_pointer_clock.boldFont ?? true
                onCheckedChanged: Config.options.background.widgets.circle_pointer_clock.boldFont = checked
            }
            ConfigSwitch {
                buttonIcon: "contrast"
                text:    Translation.tr("Black Background")
                checked: Config.options.background.widgets.circle_pointer_clock.useBlackBg ?? true
                onCheckedChanged: Config.options.background.widgets.circle_pointer_clock.useBlackBg = checked
            }
            ConfigSwitch {
                buttonIcon: "wb_twilight"
                text:    Translation.tr("Glass Reflection")
                checked: Config.options.background.widgets.circle_pointer_clock.enableGlassReflection ?? false
                onCheckedChanged: Config.options.background.widgets.circle_pointer_clock.enableGlassReflection = checked
            }
        }
    }
}
