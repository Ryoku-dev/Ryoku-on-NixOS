import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import stage.modules.common.widgets
import stage.services
import "."
import ".."

ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    RowLayout {
        visible: root.showBackButton
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
            text: Translation.tr("Dock Workspace Style Settings")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Dock Workspaces Appearance")
        icon: "dock"

        ConfigSwitch {
            buttonIcon: "radio_button_checked"
            text: Translation.tr("Show active workspace indicator")
            checked: Config.options.bar.workspaces.dockShowActiveIndicator
            onCheckedChanged: {
                Config.options.bar.workspaces.dockShowActiveIndicator = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "more_horiz"
            text: Translation.tr("Show window count dots")
            checked: Config.options.bar.workspaces.dockShowWindowDots
            onCheckedChanged: {
                Config.options.bar.workspaces.dockShowWindowDots = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Hover animations")
            checked: Config.options.bar.workspaces.dockHoverEffect
            onCheckedChanged: {
                Config.options.bar.workspaces.dockHoverEffect = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "apps"
            text: Translation.tr("Show app icons")
            checked: Config.options.bar.workspaces.dockShowAppIcons
            onCheckedChanged: {
                Config.options.bar.workspaces.dockShowAppIcons = checked;
            }
            StyledToolTip {
                text: Translation.tr("Show the first window's icon inside each workspace button")
            }
        }
    }
}
