import QtQuick
import QtQuick.Layouts
import Quickshell
import "../"
import "../../"

Item {
    id: root
    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    property real imageSize: 220
    property real textSize: 15
    property real spacing: 16
    property string text: I18n.t("notifications.center.reserved")
    property string imageSource: ""

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: root.spacing

        ImageBox {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.imageSize
            Layout.preferredHeight: root.imageSize
            source: root.imageSource !== "" ? root.imageSource : ("file://" + Caching.assetsPath + "/pushy2.gif")
            isGif: true
            playing: root.visible
            fillMode: Image.PreserveAspectFit
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.text
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.textSize
            color: ThemeBackend.subtext0
        }
    }
}
