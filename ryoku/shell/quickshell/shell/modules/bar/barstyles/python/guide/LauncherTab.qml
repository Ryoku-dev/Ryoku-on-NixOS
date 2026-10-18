import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"
import Ryoku.Ui.Singletons as Ui

Item {
    id: launcherTabRoot
    required property var rootObj
    required property int tabIndex

    function text(key, fallback) {
        const translated = I18n.t(key)
        return translated === key ? fallback : translated
    }

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1 : 0

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - rootObj.s(48), rootObj.s(560))
        spacing: rootObj.s(16)

        Text {
            Layout.fillWidth: true
            text: launcherTabRoot.text("guide.launcher.hub_title", "Launcher settings live in Ryoku Hub")
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(22)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: launcherTabRoot.text("guide.launcher.hub_desc", "Open Ryoku Hub to configure the global launcher and its shortcut.")
            color: ThemeBackend.subtext0
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(12)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        ClickButton {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: rootObj.s(40)
            horizontalPadding: rootObj.s(18)
            buttonText: launcherTabRoot.text("guide.launcher.open_hub", "Open Ryoku Hub")
            buttonIcon: "󰒓"
            accentColor: ThemeBackend.mauve
            textColor: ThemeBackend.crust
            cornerRadius: ThemeBackend.borderRadius
            onClicked: {
                rootObj.closePopup()
                Ui.Spawn.run(["ryoku-shell", "hub", "open"])
            }
        }
    }
}
