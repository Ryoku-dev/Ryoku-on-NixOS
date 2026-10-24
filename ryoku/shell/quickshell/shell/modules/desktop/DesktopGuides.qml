pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons

// The grid exists only during a drag. The controller supplies whichever screen
// centre, widget edge, or widget centre currently owns each snapped axis.
Item {
    id: guides

    property bool active: false
    property bool showGrid: true
    property real gridSize: 32
    property var verticals: []
    property var horizontals: []

    readonly property int animDur: Tokens.dur(140)

    Item {
        anchors.fill: parent
        visible: guides.active
        opacity: guides.active ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: guides.animDur
                easing.type: Easing.OutCubic
            }
        }

        Repeater {
            model: guides.active && guides.showGrid
                ? Math.max(0, Math.ceil(guides.width / guides.gridSize) - 1) : 0
            delegate: Rectangle {
                required property int index
                x: Math.round((index + 1) * guides.gridSize)
                width: Tokens.border
                height: guides.height
                color: Tokens.lineSoft
            }
        }
        Repeater {
            model: guides.active && guides.showGrid
                ? Math.max(0, Math.ceil(guides.height / guides.gridSize) - 1) : 0
            delegate: Rectangle {
                required property int index
                y: Math.round((index + 1) * guides.gridSize)
                width: guides.width
                height: Tokens.border
                color: Tokens.lineSoft
            }
        }

        Repeater {
            model: guides.verticals
            delegate: Rectangle {
                required property real modelData
                x: Math.round(modelData)
                width: Tokens.border
                height: guides.height
                color: Tokens.sun
            }
        }
        Repeater {
            model: guides.horizontals
            delegate: Rectangle {
                required property real modelData
                y: Math.round(modelData)
                width: guides.width
                height: Tokens.border
                color: Tokens.sun
            }
        }
    }

    Component {
        id: flashLine
        Rectangle {
            id: flash
            property bool vertical: true
            property real pos: 0
            x: flash.vertical ? Math.round(flash.pos) : 0
            y: flash.vertical ? 0 : Math.round(flash.pos)
            width: flash.vertical ? Tokens.border : guides.width
            height: flash.vertical ? guides.height : Tokens.border
            color: Tokens.sun
            NumberAnimation on opacity {
                from: 0.9
                to: 0
                duration: Tokens.dur(800)
                easing.type: Easing.OutCubic
                running: true
                onFinished: flash.destroy()
            }
        }
    }

    function flash(verticalLines, horizontalLines) {
        for (const x of verticalLines)
            flashLine.createObject(guides, { vertical: true, pos: x });
        for (const y of horizontalLines)
            flashLine.createObject(guides, { vertical: false, pos: y });
    }
}
