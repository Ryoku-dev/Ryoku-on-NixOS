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
            text: Translation.tr("PC Battery Cable Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("PC Battery Cable Settings")
        icon: "power"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("pc_battery_cable")

            PagePlaceholder {
                anchors.fill: parent
                icon: "power"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("PC Battery Cable widget disabled")
                description: Translation.tr("Enable the PC Battery Cable widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("pc_battery_cable")

            ContentSubsectionLabel {
                text: Translation.tr("Display")
            }

            ConfigSwitch {
                buttonIcon: "percent"
                text: Translation.tr("Show Battery Percentage")
                checked: Config.options.background.widgets.pc_battery_cable.showPercentage ?? true
                onCheckedChanged: Config.options.background.widgets.pc_battery_cable.showPercentage = checked
            }

            ConfigSwitch {
                buttonIcon: "bolt"
                text: Translation.tr("Show Charging Icon")
                checked: Config.options.background.widgets.pc_battery_cable.showChargingIcon ?? true
                onCheckedChanged: Config.options.background.widgets.pc_battery_cable.showChargingIcon = checked
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
