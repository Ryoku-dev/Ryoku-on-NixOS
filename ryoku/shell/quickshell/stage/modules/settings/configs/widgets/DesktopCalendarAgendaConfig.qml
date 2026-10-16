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
            text: Translation.tr("Calendar Agenda Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Calendar Agenda Settings")
        icon: "event"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("calendar_agenda")

            PagePlaceholder {
                anchors.fill: parent
                icon: "event"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Calendar Agenda widget disabled")
                description: Translation.tr("Enable the Calendar Agenda widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("calendar_agenda")

            ContentSubsectionLabel { text: Translation.tr("Week starts on") }
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.calendar_agenda.weekStart ?? "monday"
                onSelected: value => Config.options.background.widgets.calendar_agenda.weekStart = value
                options: [
                    { "displayName": Translation.tr("Monday"), "value": "monday" },
                    { "displayName": Translation.tr("Sunday"), "value": "sunday" }
                ]
            }

            ContentSubsectionLabel { text: Translation.tr("Events shown") }
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.calendar_agenda.maxEvents ?? 0
                onSelected: value => Config.options.background.widgets.calendar_agenda.maxEvents = value
                options: [
                    { "displayName": Translation.tr("All"), "value": 0 },
                    { "displayName": "1", "value": 1 },
                    { "displayName": "3", "value": 3 },
                    { "displayName": "5", "value": 5 }
                ]
            }

            ConfigSwitch {
                buttonIcon: "more_horiz"
                text: Translation.tr("Show event dots")
                checked: Config.options.background.widgets.calendar_agenda.showEventDots ?? true
                onCheckedChanged: Config.options.background.widgets.calendar_agenda.showEventDots = checked
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
