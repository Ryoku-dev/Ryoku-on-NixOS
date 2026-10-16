import QtQuick
import QtQuick.Layouts
import stage.modules.common
import stage.modules.common.widgets
import stage.services

ColumnLayout {
    id: root

    required property var options
    property bool expressiveColors: true
    property bool location: false
    property bool forecast: false
    property bool hourly: false
    property bool temperature: false
    property bool icon: false
    property bool background: false
    property bool feelsLike: false
    property bool condition: false
    property bool refresh: false

    Layout.fillWidth: true
    spacing: 4

    ContentSubsectionLabel {
        text: Translation.tr("Content and color")
    }

    ConfigSwitch {
        visible: root.expressiveColors
        buttonIcon: "palette"
        text: Translation.tr("Expressive colors")
        checked: root.options.expressiveColors
        onCheckedChanged: root.options.expressiveColors = checked
    }

    ConfigSwitch {
        visible: root.location
        buttonIcon: "location_on"
        text: Translation.tr("Show location")
        checked: root.location && (root.options.showLocation ?? true)
        onCheckedChanged: {
            if (root.location)
                root.options.showLocation = checked;
        }
    }

    ConfigSwitch {
        visible: root.forecast
        buttonIcon: "calendar_view_week"
        text: Translation.tr("Show forecast")
        checked: root.forecast && (root.options.showForecast ?? true)
        onCheckedChanged: {
            if (root.forecast)
                root.options.showForecast = checked;
        }
    }

    ConfigSwitch {
        visible: root.hourly
        buttonIcon: "schedule"
        text: Translation.tr("Show hourly weather")
        checked: root.hourly && (root.options.showHourly ?? true)
        onCheckedChanged: {
            if (root.hourly)
                root.options.showHourly = checked;
        }
    }

    ConfigSwitch {
        visible: root.temperature
        buttonIcon: "device_thermostat"
        text: Translation.tr("Show temperature")
        checked: root.temperature && (root.options.showTemperature ?? false)
        onCheckedChanged: {
            if (root.temperature)
                root.options.showTemperature = checked;
        }
    }

    ConfigSwitch {
        visible: root.icon
        buttonIcon: "sunny"
        text: Translation.tr("Show weather icon")
        checked: root.icon && (root.options.showIcon ?? true)
        onCheckedChanged: {
            if (root.icon)
                root.options.showIcon = checked;
        }
    }

    ConfigSwitch {
        visible: root.background
        buttonIcon: "background_dot_small"
        text: Translation.tr("Show background")
        checked: root.background && (root.options.showBackground ?? true)
        onCheckedChanged: {
            if (root.background)
                root.options.showBackground = checked;
        }
    }

    ConfigSwitch {
        visible: root.feelsLike
        buttonIcon: "thermostat"
        text: Translation.tr("Show feels-like temperature")
        checked: root.feelsLike && (root.options.showFeelsLike ?? true)
        onCheckedChanged: {
            if (root.feelsLike)
                root.options.showFeelsLike = checked;
        }
    }

    ConfigSwitch {
        visible: root.condition
        buttonIcon: "cloud"
        text: Translation.tr("Show condition")
        checked: root.condition && (root.options.showCondition ?? true)
        onCheckedChanged: {
            if (root.condition)
                root.options.showCondition = checked;
        }
    }

    ConfigSwitch {
        visible: root.refresh
        buttonIcon: "refresh"
        text: Translation.tr("Show refresh button")
        checked: root.refresh && (root.options.showRefresh ?? true)
        onCheckedChanged: {
            if (root.refresh)
                root.options.showRefresh = checked;
        }
    }

    ContentSubsectionLabel {
        text: Translation.tr("Location and units follow Ryoku Weather settings.")
    }
}
