import QtQuick
import Ryoku.Ui.Singletons

FocusScope {
    id: capture

    property string actionLabel: ""
    property string currentBinding: ""
    // A function (chord) returning a conflict message, or "" when there is none.
    property var conflictFor: function (chord) { return ""; }

    signal saved(string chord)
    signal cleared()
    signal cancelled()

    anchors.fill: parent

    property string _chord: ""
    readonly property string _conflict: capture._chord.length > 0 ? capture.conflictFor(capture._chord) : ""

    function open() {
        capture._chord = "";
        capture.visible = true;
        capture.forceActiveFocus();
    }

    function _name(key, text) {
        switch (key) {
        case Qt.Key_Left: return "left";
        case Qt.Key_Right: return "right";
        case Qt.Key_Up: return "up";
        case Qt.Key_Down: return "down";
        case Qt.Key_Return:
        case Qt.Key_Enter: return "enter";
        case Qt.Key_Tab: return "tab";
        case Qt.Key_Backtab: return "tab";
        case Qt.Key_Space: return "space";
        case Qt.Key_Backspace: return "backspace";
        case Qt.Key_Delete: return "delete";
        case Qt.Key_Home: return "home";
        case Qt.Key_End: return "end";
        case Qt.Key_PageUp: return "pageup";
        case Qt.Key_PageDown: return "pagedown";
        }
        if (text && text.length === 1 && text.trim().length === 1)
            return text.toLowerCase();
        return "";
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) { capture.cancelled(); event.accepted = true; return; }
        if (event.key === Qt.Key_Control || event.key === Qt.Key_Alt
            || event.key === Qt.Key_Shift || event.key === Qt.Key_Meta) {
            event.accepted = true;
            return;
        }
        var name = capture._name(event.key, event.text);
        if (name.length === 0) { event.accepted = true; return; }
        var parts = [];
        if (event.modifiers & Qt.ControlModifier) parts.push("ctrl");
        if (event.modifiers & Qt.AltModifier) parts.push("alt");
        if (event.modifiers & Qt.ShiftModifier) parts.push("shift");
        if (event.modifiers & Qt.MetaModifier) parts.push("super");
        parts.push(name);
        capture._chord = parts.join("+");
        event.accepted = true;
    }

    Scrim {
        anchors.fill: parent
        alpha: 0.5
        onDismissed: capture.cancelled()
    }

    ChamferPanel {
        id: panel
        anchors.centerIn: parent
        width: Math.min(capture.width - 80 * Theme.scale, 440 * Theme.scale)
        height: body.implicitHeight + 40 * Theme.scale

        Column {
            id: body
            anchors.centerIn: parent
            width: parent.width - 44 * Theme.scale
            spacing: 12 * Theme.scale

            Text {
                width: parent.width
                text: capture.actionLabel
                font.family: Theme.display
                font.pixelSize: Theme.fontTitle
                color: Theme.surfaceText
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: capture._chord.length > 0
                    ? capture._chord
                    : (capture.currentBinding.length > 0 ? capture.currentBinding : I18n.tr("Unbound"))
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.sans
                font.weight: Font.DemiBold
                font.pixelSize: Theme.fontSegment
                color: Theme.surfaceText
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: I18n.tr("Press the keys for this action.")
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBase
                color: Theme.withAlpha(Theme.surfaceText, 0.56)
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                visible: capture._conflict.length > 0
                text: capture._conflict
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBase
                color: Theme.tertiary
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 9 * Theme.scale

                FolioAction {
                    label: I18n.tr("Save")
                    enabled: capture._chord.length > 0
                    onTriggered: capture.saved(capture._chord)
                }
                FolioAction {
                    label: I18n.tr("Clear")
                    onTriggered: capture.cleared()
                }
                FolioAction {
                    label: I18n.tr("Cancel")
                    onTriggered: capture.cancelled()
                }
            }
        }
    }
}
