import QtQuick
import QtQuick.Layouts
import stage.services
import "."
import ".."

UtilityConfigPage {
    title: Translation.tr("Water")

    ContentSection {
        title: Translation.tr("Goal")
        icon: "water_drop"
        tooltip: Translation.tr("Shared with the water reminder desktop widget")

        ConfigSpinBox {
            icon: "flag"
            text: Translation.tr("Glasses per day")
            value: Config.options.background.widgets.water_reminder.dailyGoal
            from: 1
            to: 30
            onValueChanged: Config.options.background.widgets.water_reminder.dailyGoal = value
        }
        ConfigSpinBox {
            icon: "local_drink"
            text: Translation.tr("Glass size (ml)")
            value: Config.options.dock.utilities.water.glassMl
            from: 50
            to: 1000
            stepSize: 50
            onValueChanged: Config.options.dock.utilities.water.glassMl = value
        }
    }

    ContentSection {
        title: Translation.tr("Reminders")
        icon: "notifications_active"
        tooltip: Translation.tr("Remind you until the daily goal is reached")

        ConfigSwitch {
            buttonIcon: "notifications_active"
            text: Translation.tr("Enable water reminders")
            checked: Config.options.background.widgets.water_reminder.enable ?? false
            onCheckedChanged: if (checked !== Config.options.background.widgets.water_reminder.enable)
                Config.options.background.widgets.water_reminder.enable = checked
        }
        ConfigSpinBox {
            enabled: Config.options.background.widgets.water_reminder.enable ?? false
            icon: "av_timer"
            text: Translation.tr("Reminder interval (hours)")
            value: Config.options.background.widgets.water_reminder.intervalHours ?? 2
            from: 1
            to: 12
            onValueChanged: if (value !== Config.options.background.widgets.water_reminder.intervalHours)
                Config.options.background.widgets.water_reminder.intervalHours = value
        }
        ConfigTextField {
            enabled: Config.options.background.widgets.water_reminder.enable ?? false
            icon: "message"
            text: Translation.tr("Reminder message")
            placeholderText: Translation.tr("Time to hydrate! 💧")
            inputText: Config.options.background.widgets.water_reminder.reminderText
            textField.onEditingFinished: Config.options.background.widgets.water_reminder.reminderText = textField.text.trim()
        }
    }
}
