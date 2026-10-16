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
        spacing: Appearance.font.pixelSize.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: Appearance.font.pixelSize.huge * 2
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
            text: Translation.tr("At a Glance Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("At a Glance Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("at_a_glance")

            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("At a Glance disabled")
                description: Translation.tr("Enable At a Glance in Desktop Widgets settings to configure options.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 4
            visible: Config.isWidgetActive("at_a_glance")

            // ── Layout & Size ───────────────────────────────────────────────
            ContentSubsectionLabel {
                text: Translation.tr("Layout & Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Scale")
                value: Config.options.background.widgets.at_a_glance.widgetSize ?? 100
                from: 50; to: 200; stepSize: 10
                onValueChanged: Config.options.background.widgets.at_a_glance.widgetSize = value
            }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.at_a_glance.widthCells ?? 3
                options: [
                    { displayName: Translation.tr("2x1 Compact"), icon: "view_week", value: 2 },
                    { displayName: Translation.tr("3x1 Full"), icon: "view_column", value: 3 }
                ]
                onSelected: value => Config.options.background.widgets.at_a_glance.widthCells = value
            }

            ConfigSwitch {
                buttonIcon: "view_stream"
                text: Translation.tr("Dual-Column Mode (display 2 targets)")
                checked: Config.options.background.widgets.at_a_glance.dualColumnMode ?? false
                onCheckedChanged: Config.options.background.widgets.at_a_glance.dualColumnMode = checked
            }

            // ── Context Sources ──────────────────────────────────────────────
            ContentSubsectionLabel {
                text: Translation.tr("Smart Context Sources")
            }

            ConfigSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Use media context")
                checked: Config.options.background.widgets.at_a_glance.enableMedia ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableMedia = checked
            }

            ConfigSwitch {
                buttonIcon: "event"
                text: Translation.tr("Use calendar context")
                checked: Config.options.background.widgets.at_a_glance.enableCalendar ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableCalendar = checked
            }

            ConfigSwitch {
                buttonIcon: "sports_soccer"
                text: Translation.tr("Use sports context")
                checked: Config.options.background.widgets.at_a_glance.enableSports ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableSports = checked
            }

            ConfigSwitch {
                buttonIcon: "task_alt"
                text: Translation.tr("Use To-Do context")
                checked: Config.options.background.widgets.at_a_glance.enableTodo ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableTodo = checked
            }

            ConfigSwitch {
                buttonIcon: "mail"
                text: Translation.tr("Use email context")
                checked: Config.options.background.widgets.at_a_glance.enableEmail ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableEmail = checked
            }

            ConfigSwitch {
                buttonIcon: "share"
                text: Translation.tr("Use LocalSend context")
                checked: Config.options.background.widgets.at_a_glance.enableLocalSend ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableLocalSend = checked
            }

            ConfigSwitch {
                buttonIcon: "smartphone"
                text: Translation.tr("Use KDE Connect context")
                checked: Config.options.background.widgets.at_a_glance.enableKdeConnect ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableKdeConnect = checked
            }

            ConfigSwitch {
                buttonIcon: "cloud"
                text: Translation.tr("Show weather info")
                checked: Config.options.background.widgets.at_a_glance.enableWeather ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableWeather = checked
            }

            // ── Context Windows ──────────────────────────────────────────────
            ContentSubsectionLabel {
                text: Translation.tr("Context Windows")
            }

            ConfigSpinBox {
                icon: "event_upcoming"
                text: Translation.tr("Calendar window (minutes)")
                value: Config.options.background.widgets.at_a_glance.calendarWindowMinutes ?? 60
                from: 0
                to: 720
                stepSize: 15
                onValueChanged: Config.options.background.widgets.at_a_glance.calendarWindowMinutes = value
            }

            ConfigSpinBox {
                icon: "schedule"
                text: Translation.tr("Sports window (hours)")
                value: Config.options.background.widgets.at_a_glance.sportsWindowHours ?? 12
                from: 0
                to: 168
                stepSize: 1
                onValueChanged: Config.options.background.widgets.at_a_glance.sportsWindowHours = value
            }
        }
    }
}
