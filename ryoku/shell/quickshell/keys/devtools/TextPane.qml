import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

Rectangle {
    id: root

    property alias text: editor.text
    readonly property bool focused: editor.activeFocus
    property string placeholder: ""
    property bool readOnly: false
    property bool error: false
    signal edited(string value)

    radius: Tokens.radius
    color: Tokens.paperLift
    border.width: editor.activeFocus ? 2 : Tokens.border
    border.color: root.error ? Tokens.alert : (editor.activeFocus ? Tokens.ink : (hover.hovered ? Tokens.lineStrong : Tokens.line))
    clip: true
    Behavior on border.color {
        enabled: !Tokens.reduceMotion
        ColorAnimation { duration: Tokens.snap }
    }
    HoverHandler { id: hover; cursorShape: root.readOnly ? Qt.ArrowCursor : Qt.IBeamCursor }

    function grabFocus() {
        editor.forceActiveFocus();
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        anchors.margins: Tokens.s3
        contentWidth: width
        contentHeight: Math.max(height, editor.implicitHeight)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        TextEdit {
            id: editor
            width: scroller.width
            height: Math.max(scroller.height, implicitHeight)
            color: root.error ? Tokens.alert : Tokens.ink
            selectionColor: Tokens.bone
            selectedTextColor: Tokens.inkOnBone
            font.family: Tokens.mono
            font.pixelSize: Tokens.fSmall
            wrapMode: TextEdit.Wrap
            readOnly: root.readOnly
            selectByMouse: true
            textFormat: TextEdit.PlainText
            onTextChanged: if (!root.readOnly && activeFocus) root.edited(text)
        }

        Text {
            anchors.top: parent.top
            visible: editor.text.length === 0
            text: root.placeholder
            color: Tokens.inkMuted
            font: editor.font
        }

        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }
        WheelScroll { }
    }
}
