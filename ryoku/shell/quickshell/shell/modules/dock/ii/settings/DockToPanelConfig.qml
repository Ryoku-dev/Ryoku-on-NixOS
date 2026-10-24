import QtQuick
import QtQuick.Layouts
import stage.modules.common.widgets
import stage.services
import "."
import ".."

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

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
            text: Translation.tr("Dock to Panel")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Dock to Panel")

        ConfigSpinBox {
            icon: "height"
            text: Translation.tr("Icon size")
            value: Config.options.dockToPanel.iconSize
            from: 17
            to: 40
            stepSize: 1
            onValueChanged: {
                Config.options.dockToPanel.iconSize = value;
            }
        }
        ConfigSpinBox {
            icon: "format_letter_spacing"
            text: Translation.tr("Button spacing")
            value: Config.options.dockToPanel.buttonSpacing
            from: 0
            to: 10
            stepSize: 1
            onValueChanged: {
                Config.options.dockToPanel.buttonSpacing = value;
            }
        }
        ConfigSwitch {
            buttonIcon: "swap_calls"
            text: Translation.tr("Enable workspace scrolling")
            checked: Config.options.dockToPanel.enableWorkspaceScroll
            onCheckedChanged: {
                Config.options.dockToPanel.enableWorkspaceScroll = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "grid_view"
            text: Translation.tr("Align apps to current workspace")
            checked: Config.options.dockToPanel.alignToWorkspace
            onCheckedChanged: {
                Config.options.dockToPanel.alignToWorkspace = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "subtitles"
            text: Translation.tr("Enable app name tooltips")
            checked: Config.options.dockToPanel.enableTooltip
            onCheckedChanged: {
                Config.options.dockToPanel.enableTooltip = checked;
                if (checked) {
                    Config.options.dockToPanel.enablePreview = false;
                }
            }
        }
        ConfigSwitch {
            buttonIcon: "preview"
            text: Translation.tr("Enable window preview popups")
            checked: Config.options.dockToPanel.enablePreview
            onCheckedChanged: {
                Config.options.dockToPanel.enablePreview = checked;
                if (checked) {
                    Config.options.dockToPanel.enableTooltip = false;
                }
            }
        }
        ConfigSwitch {
            buttonIcon: "zoom_in"
            text: Translation.tr("Enable macOS icon magnification")
            checked: Config.options.dockToPanel.enableMacOsMagnification
            onCheckedChanged: {
                Config.options.dockToPanel.enableMacOsMagnification = checked;
            }
        }
        ConfigSpinBox {
            visible: Config.options.dockToPanel.enableMacOsMagnification ?? false
            icon: "zoom_in_map"
            text: Translation.tr("Magnification intensity (%)")
            value: Math.round((Config.options.dockToPanel.macOsMagnificationScale ?? 1.6) * 100)
            from: 120
            to: 220
            stepSize: 10
            onValueChanged: {
                Config.options.dockToPanel.macOsMagnificationScale = value / 100.0;
            }
        }
        NoticeBox {
            visible: Config.options.bar?.onlyShowOnSingleMonitor ?? false
            Layout.fillWidth: true
            text: Translation.tr("Isolate monitors requires 'Show bar only on a single monitor' to be disabled.")
        }
        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Isolate monitors (show unpinned apps per monitor)")
            checked: Config.options.dockToPanel.isolateMonitors ?? false
            enabled: !(Config.options.bar?.onlyShowOnSingleMonitor ?? false)
            onCheckedChanged: {
                Config.options.dockToPanel.isolateMonitors = checked;
                if (checked && Config.options.bar) {
                    Config.options.bar.onlyShowOnSingleMonitor = false;
                }
            }
        }
    }
}
