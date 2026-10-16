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
            text: Translation.tr("Calendar Upcoming 3 Days Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Calendar Upcoming 3 Days Settings")
        icon: "calendar_view_day"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("calendar_upcoming_3days")

            PagePlaceholder {
                anchors.fill: parent
                icon: "calendar_view_day"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Calendar Upcoming 3 Days widget disabled")
                description: Translation.tr("Enable the Calendar Upcoming 3 Days widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("calendar_upcoming_3days")

            ContentSubsectionLabel { text: Translation.tr("Days shown") }
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.calendar_upcoming_3days.daysShown ?? 3
                onSelected: value => Config.options.background.widgets.calendar_upcoming_3days.daysShown = value
                options: [
                    { "displayName": "1", "value": 1 },
                    { "displayName": "2", "value": 2 },
                    { "displayName": "3", "value": 3 }
                ]
            }

            ContentSubsectionLabel { text: Translation.tr("Events per day") }
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.calendar_upcoming_3days.maxEventsPerDay ?? 0
                onSelected: value => Config.options.background.widgets.calendar_upcoming_3days.maxEventsPerDay = value
                options: [
                    { "displayName": Translation.tr("All"), "value": 0 },
                    { "displayName": "1", "value": 1 },
                    { "displayName": "2", "value": 2 },
                    { "displayName": "3", "value": 3 }
                ]
            }

            ConfigSwitch {
                buttonIcon: "add"
                text: Translation.tr("Show add event button")
                checked: Config.options.background.widgets.calendar_upcoming_3days.showAddButton ?? true
                onCheckedChanged: Config.options.background.widgets.calendar_upcoming_3days.showAddButton = checked
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
