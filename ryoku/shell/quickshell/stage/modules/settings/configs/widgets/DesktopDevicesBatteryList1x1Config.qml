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
            text: Translation.tr("Devices Battery List 1x1 Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Devices Battery List 1x1 Settings")
        icon: "battery_full"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("devices_battery_list_1x1")

            PagePlaceholder {
                anchors.fill: parent
                icon: "battery_full"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Devices Battery List 1x1 widget disabled")
                description: Translation.tr("Enable the Devices Battery List 1x1 widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("devices_battery_list_1x1")

            ContentSubsectionLabel {
                text: Translation.tr("Display")
            }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.devices_battery_list_1x1.maxDevices ?? 4
                onSelected: value => Config.options.background.widgets.devices_battery_list_1x1.maxDevices = Number(value)
                options: [
                    { displayName: Translation.tr("1 Device"), icon: "filter_1", value: 1 },
                    { displayName: Translation.tr("2 Devices"), icon: "filter_2", value: 2 },
                    { displayName: Translation.tr("3 Devices"), icon: "filter_3", value: 3 },
                    { displayName: Translation.tr("4 Devices"), icon: "filter_4", value: 4 }
                ]
            }

            ConfigSwitch {
                buttonIcon: "label"
                text: Translation.tr("Show Device Names")
                checked: Config.options.background.widgets.devices_battery_list_1x1.showDeviceName ?? true
                onCheckedChanged: Config.options.background.widgets.devices_battery_list_1x1.showDeviceName = checked
            }

            ConfigSwitch {
                buttonIcon: "percent"
                text: Translation.tr("Show Battery Percentages")
                checked: Config.options.background.widgets.devices_battery_list_1x1.showPercentage ?? true
                onCheckedChanged: Config.options.background.widgets.devices_battery_list_1x1.showPercentage = checked
            }

            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.enableShadows ?? true
                onCheckedChanged: Config.options.background.widgets.enableShadows = checked
            }
        }
    }
}
