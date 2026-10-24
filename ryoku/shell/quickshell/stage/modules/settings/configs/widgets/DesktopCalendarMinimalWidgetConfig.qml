import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.settings.configs.widgets

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
            text: Translation.tr("Calendar Minimal Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Calendar Minimal Settings")
        icon: "calendar_today"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("calendar_minimal")

            PagePlaceholder {
                anchors.fill: parent
                icon: "calendar_today"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Calendar Minimal widget disabled")
                description: Translation.tr("Enable the Calendar Minimal widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("calendar_minimal")

            ContentSubsectionLabel { text: Translation.tr("Weekday label") }
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.calendar_minimal.weekdayFormat ?? "dddd"
                onSelected: value => Config.options.background.widgets.calendar_minimal.weekdayFormat = value
                options: [
                    { "displayName": Translation.tr("Full"), "value": "dddd" },
                    { "displayName": Translation.tr("Short"), "value": "ddd" }
                ]
            }

            ContentSubsectionLabel { text: Translation.tr("Month label") }
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.calendar_minimal.monthFormat ?? "MMMM"
                onSelected: value => Config.options.background.widgets.calendar_minimal.monthFormat = value
                options: [
                    { "displayName": Translation.tr("Full"), "value": "MMMM" },
                    { "displayName": Translation.tr("Short"), "value": "MMM" }
                ]
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
