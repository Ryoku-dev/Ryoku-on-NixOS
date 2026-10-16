import QtQuick
import QtQuick.Layouts
import stage.modules.common
import stage.modules.common.widgets
import stage.services
import stage.modules.settings.configs.widgets

/**
 * Shared settings surface for both EasyEffects preset shapes. The host supplies
 * the selected registry id; the two registry wrappers provide the same value
 * when this page is opened from the Stage Editor.
 */
ContentPage {
    id: root

    signal goBack()

    property string widget: ""
    property string widgetId: String(root.widget).indexOf("Landscape") >= 0
        || root.widget === "easyeffects_preset_landscape"
        ? "easyeffects_preset_landscape" : "easyeffects_preset_portrait"
    readonly property bool landscape: root.widgetId === "easyeffects_preset_landscape"
    readonly property var options: Config.options.easyEffects.widget
    readonly property bool placed: Config.isWidgetActive(root.widgetId)

    forceWidth: false

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
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: root.landscape
                ? Translation.tr("EasyEffects Preset Landscape Options")
                : Translation.tr("EasyEffects Preset Portrait Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: 250
        visible: !root.placed

        PagePlaceholder {
            anchors.fill: parent
            icon: "graphic_eq"
            shape: MaterialShape.Shape.Circle
            title: root.landscape
                ? Translation.tr("EasyEffects Preset landscape widget disabled")
                : Translation.tr("EasyEffects Preset portrait widget disabled")
            description: Translation.tr("Add this EasyEffects Preset widget to the desktop to use this page.")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 16
        visible: root.placed

        ContentSection {
            title: Translation.tr("Texture")
            icon: "ssid_chart"

            ConfigSwitch {
                buttonIcon: "ssid_chart"
                text: Translation.tr("Contour lines")
                description: Translation.tr("The fine topographic lines behind the card. Off leaves the plain surface.")
                checked: root.options.topography
                onCheckedChanged: root.options.topography = checked
            }

            ConfigSwitch {
                buttonIcon: "music_note"
                enabled: root.options.topography
                text: Translation.tr("Follow the music")
                description: Translation.tr("The lines speed up and swell with the beat of what is playing. Off, they only drift slowly.")
                checked: root.options.topographyReactive
                onCheckedChanged: root.options.topographyReactive = checked
            }

            ConfigSwitch {
                buttonIcon: "pause_circle"
                enabled: root.options.topography
                text: Translation.tr("Pause under open windows")
                description: Translation.tr("Hold the lines still while a program is open on the workspace being shown, so the animation doesn't use the GPU while nobody sees it.")
                checked: root.options.pauseOnWindows
                onCheckedChanged: root.options.pauseOnWindows = checked
            }

            ConfigSlider {
                buttonIcon: "opacity"
                enabled: root.options.topography
                text: Translation.tr("Line opacity")
                usePercentTooltip: false
                tooltipContent: `${Math.round(value)}%`
                value: root.options.topographyStrength
                from: 20
                to: 200
                stepSize: 5
                onValueChanged: root.options.topographyStrength = Math.round(value)
            }
        }

        ContentSection {
            title: Translation.tr("Content")
            icon: "dashboard_customize"

            ContentSubsectionLabel {
                text: Translation.tr("Centrepiece")
            }

            ConfigSelectionArray {
                currentValue: root.options.art
                onSelected: newValue => root.options.art = String(newValue)
                options: [
                    { displayName: Translation.tr("Shape"), icon: "interests", value: "shape" },
                    { displayName: Translation.tr("Tone curve"), icon: "show_chart", value: "curve" },
                    { displayName: Translation.tr("None"), icon: "block", value: "none" }
                ]
            }

            ConfigSwitch {
                buttonIcon: "speaker"
                text: Translation.tr("Device")
                description: Translation.tr("The pill naming the device the preset plays through.")
                checked: root.options.showDevice
                onCheckedChanged: root.options.showDevice = checked
            }

            ConfigSwitch {
                buttonIcon: "play_circle"
                text: Translation.tr("State")
                description: Translation.tr("The pill saying whether the effects are playing, bypassed or off.")
                checked: root.options.showState
                onCheckedChanged: root.options.showState = checked
            }

            ConfigSwitch {
                buttonIcon: "star"
                text: Translation.tr("Device default")
                description: Translation.tr("The pill with the preset this device starts with; when it isn't the one loaded, click it to load it.")
                checked: root.options.showDefault
                onCheckedChanged: root.options.showDefault = checked
            }

            ConfigSwitch {
                buttonIcon: "waves"
                text: Translation.tr("Wave")
                checked: root.options.showWave
                onCheckedChanged: root.options.showWave = checked
            }

            ConfigSwitch {
                buttonIcon: "label"
                text: Translation.tr("Family")
                description: Translation.tr("The small line above the name: the preset's family and whether it is the device default.")
                checked: root.options.showCaption
                onCheckedChanged: root.options.showCaption = checked
            }

            ConfigSwitch {
                buttonIcon: "title"
                text: Translation.tr("Preset name")
                checked: root.options.showName
                onCheckedChanged: root.options.showName = checked
            }

            ConfigSwitch {
                buttonIcon: "instant_mix"
                text: Translation.tr("Effects in the chain")
                checked: root.options.showEffects
                onCheckedChanged: root.options.showEffects = checked
            }

            ConfigSwitch {
                buttonIcon: "smart_button"
                text: Translation.tr("Buttons")
                description: Translation.tr("Edit effects and Bypass. Off, the card is only to look at.")
                checked: root.options.showButtons
                onCheckedChanged: root.options.showButtons = checked
            }
        }

        ContentSection {
            title: Translation.tr("Source")
            icon: "settings_input_component"

            ContentSubsectionLabel {
                text: Translation.tr("Show the preset of")
            }

            ConfigSelectionArray {
                currentValue: root.options.pipeline
                onSelected: newValue => root.options.pipeline = String(newValue)
                options: [
                    { displayName: Translation.tr("Output"), icon: "speaker", value: "output" },
                    { displayName: Translation.tr("Input"), icon: "mic", value: "input" }
                ]
            }
        }

    }
}
