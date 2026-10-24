import QtQuick
import QtQuick.Layouts
import Quickshell
import stage
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.ii.background.widgets
import stage.services
import shell.services as ShellServices
AbstractBackgroundWidget {
    id: root

    property bool wallpaperSafetyTriggered: false
    // State and actions come from the shell's canonical recorder.
    readonly property bool isActive: ShellServices.Recorder.active
    readonly property color pillBgColor: isActive ? WidgetColorScheme.accentColor : WidgetColorScheme.cardBgColor
    readonly property color contentColor: isActive ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg

    configEntryName: "screen_record_pill"
    implicitWidth: 240
    implicitHeight: 120

    // Shadow Effect
    StyledDropShadow {
        id: shadowEffect

        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer

        anchors.fill: parent
        radius: height / 2
        color: WidgetColorScheme.tintBackground(root.pillBgColor)

        // Icon Button (Large circular click area on the left)
        RippleButton {
            id: iconButton

            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 64
            implicitHeight: 64
            topLeftRadius: 37
            topRightRadius: 37
            bottomLeftRadius: 37
            bottomRightRadius: 37
            colBackground: "transparent"
            colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.15)
            colRipple: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.3)
            onClicked: {
                if (root.isActive)
                    ShellServices.Recorder.stop();
                else
                    ShellServices.Recorder.start(ShellServices.Recorder.recordArgs());
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.isActive ? "stop" : "videocam"
                iconSize: 38
                color: root.contentColor

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }

                }

            }

        }

        // Label Text (Positioned close to the Icon Button)
        StyledText {
            anchors.left: iconButton.right
            anchors.leftMargin: 0
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.isActive ? Translation.tr("Recording") : Translation.tr("Record")
            font.pixelSize: 24
            font.weight: Font.Bold
            color: root.contentColor
            elide: Text.ElideRight

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }

            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }

        }

    }

}
