pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root
    property real s: 1
    property var options: []
    property var labels: ({})
    property string current: ""
    signal chose(string key)

    implicitWidth: measure.implicitWidth
    implicitHeight: choices.implicitHeight
    width: parent ? Math.min(implicitWidth, parent.width) : implicitWidth
    function label(value) { return I18n.tr(labels[value] !== undefined ? labels[value] : value); }
    Row {
        id: measure
        visible: false
        spacing: Tokens.s2 * root.s
        Repeater {
            model: root.options
            Text {
                required property string modelData
                text: root.label(modelData)
                font.family: Tokens.ui
                font.pixelSize: Tokens.fRow * root.s
                font.weight: Font.Medium
                width: implicitWidth + Tokens.s3 * root.s * 2
            }
        }
    }
    Flow {
        id: choices
        width: root.width
        spacing: Tokens.s2 * root.s
        Repeater {
            model: root.options
            SidebarButton {
                required property string modelData
                s: root.s
                text: root.label(modelData)
                width: Math.min(implicitWidth, choices.width)
                primary: root.current === modelData
                Accessible.role: Accessible.RadioButton
                Accessible.checkable: true
                Accessible.checked: primary
                onAct: root.chose(modelData)
            }
        }
    }
}
