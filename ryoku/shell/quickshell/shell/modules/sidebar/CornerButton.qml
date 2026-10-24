pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui.Singletons
import shell.services

QQC.AbstractButton {
    id: root
    property real s: 1
    property string glyph: ""
    property bool emphasis: false
    property bool subtle: false
    readonly property bool accented: checked || emphasis
    readonly property color plate: Tokens.role("primaryContainer", Tokens.tint16)
    readonly property color accentInk: Tokens.role("onPrimaryContainer", Tokens.ink)
    readonly property bool motionAllowed: !Tokens.reduceMotion && !Motion.reduce

    hoverEnabled: true
    implicitHeight: 36 * s
    implicitWidth: text === "" ? implicitHeight : Math.ceil(label.implicitWidth + (glyph !== "" ? 26 * s : 0) + 24 * s)
    padding: 10 * s
    opacity: enabled ? 1 : 0.42
    Accessible.name: text
    background: Rectangle {
        radius: Tokens.radius * root.s * 1.5
        color: root.accented ? root.plate : root.down ? Tokens.tint16 : root.hovered ? Tokens.tint10 : root.subtle ? "transparent" : Tokens.tint5
        border.width: Tokens.border
        border.color: root.visualFocus ? Tokens.sun : root.accented ? Qt.alpha(Tokens.sun, 0.2) : "transparent"
        Behavior on color { enabled: root.motionAllowed; ColorAnimation { duration: Tokens.snap } }
    }
    contentItem: Item {
        implicitWidth: label.implicitWidth + (root.glyph !== "" ? 26 * root.s : 0)
        Text {
            id: icon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.text === "" ? parent.width : 20 * root.s
            visible: root.glyph !== ""
            text: root.glyph
            color: root.accented ? root.accentInk : Tokens.inkDim
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20 * root.s
            horizontalAlignment: Text.AlignHCenter
            Accessible.ignored: true
            scale: root.down ? 0.9 : 1
            Behavior on scale { enabled: root.motionAllowed; NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap } }
        }
        Text {
            id: label
            anchors.left: root.glyph !== "" ? icon.right : parent.left
            anchors.leftMargin: root.glyph !== "" ? 6 * root.s : 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            color: root.accented ? root.accentInk : Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall * root.s
            font.weight: Font.Medium
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }
    CornerTip { s: root.s; visible: root.hovered && (root.text === "" || label.truncated); text: root.Accessible.name }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
