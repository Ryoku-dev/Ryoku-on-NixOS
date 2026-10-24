pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui.Singletons
import shell.services

QQC.ToolTip {
    id: root
    property real s: 1

    delay: Tokens.swap
    timeout: 6000
    padding: Tokens.s2 * s
    margins: Tokens.s1 * s
    y: -implicitHeight - Tokens.s2 * s
    enter: Transition {
        enabled: !Tokens.reduceMotion && !Motion.reduce
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.snap; easing.type: Tokens.easeSnap }
    }
    exit: Transition {
        enabled: !Tokens.reduceMotion && !Motion.reduce
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.snap; easing.type: Tokens.easeSnap }
    }
    background: Rectangle {
        radius: Tokens.radius * root.s
        color: Tokens.bone
        border.width: Tokens.border
        border.color: Tokens.line
    }
    contentItem: Text {
        text: root.text
        color: Tokens.inkOnBone
        font.family: Tokens.ui
        font.pixelSize: Tokens.fSmall * root.s
        font.weight: Font.Medium
        wrapMode: Text.NoWrap
    }
}
