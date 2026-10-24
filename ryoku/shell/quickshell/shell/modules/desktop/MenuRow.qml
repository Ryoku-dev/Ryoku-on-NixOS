pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"
import Ryoku.Ui.Singletons

// The row keeps its trailing state readable without letting translated labels
// push through it when a Stage sheet is narrower than a desktop menu.
Item {
    id: row

    property string label: ""
    property string value: ""
    property string icon: ""
    property bool on: false
    property bool accent: false
    property bool closeOnTrigger: true
    signal triggered()

    width: parent ? parent.width : 0
    implicitHeight: 34
    implicitWidth: (glyph.visible ? 9 + glyph.width + 7 : 9)
        + lbl.implicitWidth
        + (val.text.length > 0 ? 13 + val.implicitWidth : 0)
        + 9

    function closeMenu() {
        var p = row.parent;
        while (p) {
            if (p.ryoMenu === true) {
                p.close();
                return;
            }
            p = p.parent;
        }
    }

    scale: ma.pressed ? 0.94 : 1
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: row.on || row.accent ? Theme.bone
            : ma.pressed ? Theme.tilePress
            : ma.containsMouse ? Theme.tileHover : "transparent"
        border.width: 1
        border.color: row.on || row.accent ? Theme.bone
            : ma.containsMouse ? Theme.lineStrong : Theme.line
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
    }

    Text {
        id: glyph
        visible: row.icon.length > 0
        anchors {
            left: parent.left
            leftMargin: 9
            verticalCenter: parent.verticalCenter
        }
        width: visible ? 20 : 0
        horizontalAlignment: Text.AlignHCenter
        text: row.icon
        color: row.on || row.accent ? Theme.inkOnBone : (ma.containsMouse ? Theme.ink : Theme.inkDim)
        font.family: Theme.iconFont
        font.pixelSize: 16
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    Text {
        id: lbl
        anchors {
            left: parent.left
            leftMargin: glyph.visible ? 9 + glyph.width + 7 : 9
            right: val.text.length > 0 ? val.left : parent.right
            rightMargin: val.text.length > 0 ? 13 : 9
            verticalCenter: parent.verticalCenter
        }
        text: I18n.tr(row.label)
        color: row.on || row.accent ? Theme.inkOnBone : (ma.containsMouse ? Theme.ink : Theme.inkSoft)
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    Text {
        id: val
        anchors {
            right: parent.right
            rightMargin: 9
            verticalCenter: parent.verticalCenter
        }
        width: text.length > 0 ? Math.min(implicitWidth, Math.max(0, row.width * 0.38)) : 0
        horizontalAlignment: Text.AlignRight
        text: row.value.length > 0 ? row.value : row.on ? I18n.tr("On") : ""
        color: row.on || row.accent ? Theme.inkOnBone : (ma.containsMouse ? Theme.ink : Theme.inkDim)
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: Font.Medium
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            row.triggered();
            if (row.closeOnTrigger)
                row.closeMenu();
        }
    }
}
