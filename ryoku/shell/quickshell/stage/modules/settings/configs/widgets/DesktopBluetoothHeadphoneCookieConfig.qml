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
            text: Translation.tr("Bluetooth Headphone Cookie Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Bluetooth Headphone Cookie Settings")
        icon: "headphones"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("bluetooth_headphone_cookie")

            PagePlaceholder {
                anchors.fill: parent
                icon: "headphones"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Headphone Cookie widget disabled")
                description: Translation.tr("Enable the Headphone Cookie widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("bluetooth_headphone_cookie")

            ContentSubsectionLabel {
                text: Translation.tr("Display")
            }

            ConfigSwitch {
                buttonIcon: "percent"
                text: Translation.tr("Show Battery Percentage")
                checked: Config.options.background.widgets.bluetooth_headphone_cookie.showPercentage ?? true
                onCheckedChanged: Config.options.background.widgets.bluetooth_headphone_cookie.showPercentage = checked
            }

            ContentSubsection {
                title: Translation.tr("Background Shape")
                icon: "category"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.bluetooth_headphone_cookie.materialShape ?? "Cookie12Sided"
                    onSelected: value => Config.options.background.widgets.bluetooth_headphone_cookie.materialShape = value
                    options: ["Circle", "Pill", "Oval", "SemiCircle", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Puffy", "PuffyDiamond", "Bun", "SoftBurst", "Sunny", "VerySunny"].map(shapeName => {
                        return {
                            displayName: "",
                            shape: shapeName,
                            value: shapeName
                        };
                    })
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
