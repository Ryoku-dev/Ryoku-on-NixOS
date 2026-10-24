pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"
import Ryoku.Ui.Singletons

// Stage sheets can be narrower than desktop menus, so the label and readout
// surrender width before the Folio-style track is allowed to collapse.
Item {
    id: sld

    property string label: ""
    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0.01
    property int decimals: 2
    property string valueText: sld.value.toFixed(sld.decimals)

    signal moved(real v)
    signal released(real v)

    width: parent ? parent.width : 0
    implicitHeight: 34
    implicitWidth: 9 + lbl.implicitWidth + 13 + 160 + 13 + val.implicitWidth + 9

    readonly property real frac: sld.to > sld.from
        ? Math.max(0, Math.min(1, (sld.value - sld.from) / (sld.to - sld.from))) : 0

    Text {
        id: lbl
        anchors {
            left: parent.left
            leftMargin: 9
            verticalCenter: parent.verticalCenter
        }
        width: Math.min(implicitWidth, Math.max(0,
            sld.width - 18 - 26 - 56 - val.width))
        text: I18n.tr(sld.label)
        color: Theme.inkSoft
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Text {
        id: val
        anchors {
            right: parent.right
            rightMargin: 9
            verticalCenter: parent.verticalCenter
        }
        width: Math.min(implicitWidth, Math.max(0, sld.width * 0.22))
        horizontalAlignment: Text.AlignRight
        text: sld.valueText
        color: Theme.inkDim
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.mono
        font.pixelSize: 9
        font.weight: Font.Medium
    }

    Item {
        id: track
        x: lbl.x + lbl.width + 13
        width: Math.max(0, val.x - 13 - x)
        height: 26
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 2
            radius: 1
            color: Theme.line
            Rectangle {
                width: Math.round(parent.width * sld.frac)
                height: parent.height
                radius: 1
                color: Theme.ink
            }
        }

        Rectangle {
            width: 12
            height: 12
            radius: 6
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.round((track.width - width) * sld.frac))
            color: Theme.surface
            border.width: 1
            border.color: Theme.ink
            scale: drag.pressed ? 1.25 : drag.containsMouse ? 1.15 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: 2.4
                }
            }
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -7
            preventStealing: true
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function at(mx) {
                const fr = Math.max(0, Math.min(1, mx / Math.max(1, track.width)));
                const v = sld.from + fr * (sld.to - sld.from);
                return Math.max(sld.from, Math.min(sld.to, Math.round(v / sld.step) * sld.step));
            }
            onPressed: (m) => sld.moved(at(m.x))
            onPositionChanged: (m) => { if (pressed) sld.moved(at(m.x)); }
            onReleased: (m) => sld.released(at(m.x))
        }
    }
}
