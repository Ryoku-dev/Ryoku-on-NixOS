pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"
import Ryoku.Ui.Singletons

// A single-line text entry for the desktop context menu, filling the gap the
// menu family carried: MenuRow and MenuSlider have no keyboard input. A quiet
// tracked eyebrow label sits over a bordered field in the menu-tile idiom; the
// value commits once -- on Enter or when focus leaves -- so a daemon write never
// fires per keystroke. The host menu window holds keyboard OnDemand while a menu
// is open, so the field types the way the colour picker's hex field already
// does.
Item {
    id: field

    property string label: ""
    property string placeholder: ""
    property string text: ""
    property var normalize: null
    property var validate: null
    property bool commitOnFocusLoss: true
    property bool showSwatch: false
    property string invalidMessage: ""
    readonly property string draft: input.text
    readonly property string normalizedDraft: field.normalize
        ? field.normalize(input.text) : input.text
    readonly property bool invalid: input.dirty && field.validate
        && !field.validate(field.normalizedDraft)
    signal committed(string value)

    width: parent ? parent.width : 0
    implicitHeight: lbl.implicitHeight + Theme.s1 + box.height
        + (field.invalid && field.invalidMessage.length > 0
            ? Theme.s1 + errorText.implicitHeight : 0)
    // A field grows the card only to a readable minimum, never to its content:
    // long poster copy scrolls inside the fixed box instead of stretching it.
    implicitWidth: Math.max(lbl.implicitWidth + Theme.s3 * 2, Theme.s7 * 4)

    Text {
        id: lbl
        anchors { left: parent.left; leftMargin: Theme.s3; top: parent.top }
        text: I18n.tr(field.label)
        color: Theme.inkDim
        font.family: Theme.font
        font.pixelSize: Theme.fMicro
        font.weight: Font.DemiBold
        font.letterSpacing: Theme.trackMark
    }

    Rectangle {
        id: box
        anchors {
            left: parent.left; leftMargin: Theme.s3
            right: parent.right; rightMargin: Theme.s3
            top: lbl.bottom; topMargin: Theme.s1
        }
        height: Theme.ctlH + Theme.s2
        radius: Theme.menuTileRadius
        color: Theme.tile
        border.width: input.activeFocus || field.invalid ? 2 : 1
        border.color: field.invalid ? Theme.brand
            : input.activeFocus ? Theme.ink : Theme.line
        Behavior on border.color { ColorAnimation { duration: Theme.quick } }

        Rectangle {
            id: swatch
            visible: field.showSwatch
            anchors.left: parent.left
            anchors.leftMargin: Theme.s2
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.ctlH - Theme.s2
            height: width
            radius: Theme.menuTileRadius
            color: field.validate && field.validate(field.normalizedDraft)
                ? field.normalizedDraft : "transparent"
            border.width: 1
            border.color: field.invalid ? Theme.brand : Theme.lineStrong
        }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: Theme.s2
                + (field.showSwatch ? swatch.width + Theme.s2 : 0)
            anchors.rightMargin: Theme.s2
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.ink
            font.family: Theme.font
            font.pixelSize: Theme.fSmall
            selectByMouse: true
            text: field.text
            property bool dirty: false
            property bool suppressFinish: false

            onActiveFocusChanged: if (activeFocus) selectAll()
            onTextEdited: input.dirty = true

            function restore() {
                text = Qt.binding(function () { return field.text; });
                input.dirty = false;
            }
            function commit() {
                const value = field.normalizedDraft;
                if (field.validate && !field.validate(value)) {
                    input.dirty = true;
                    return false;
                }
                field.committed(value);
                input.restore();
                return true;
            }
            function accept() {
                if (!input.commit())
                    return;
                input.suppressFinish = true;
                input.focus = false;
                Qt.callLater(function () { input.suppressFinish = false; });
            }

            Keys.onReturnPressed: event => {
                input.accept();
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                input.accept();
                event.accepted = true;
            }
            Keys.onEscapePressed: event => {
                input.restore();
                input.suppressFinish = true;
                input.focus = false;
                Qt.callLater(function () { input.suppressFinish = false; });
                event.accepted = true;
            }
            onEditingFinished: {
                if (input.suppressFinish)
                    return;
                if (field.commitOnFocusLoss)
                    input.commit();
                else
                    input.restore();
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: input.text.length === 0 && !input.activeFocus
                text: I18n.tr(field.placeholder)
                color: Theme.inkDim
                font: input.font
                elide: Text.ElideRight
            }
        }
    }

    Text {
        id: errorText
        anchors {
            left: box.left
            right: box.right
            top: box.bottom
            topMargin: Theme.s1
        }
        visible: field.invalid && field.invalidMessage.length > 0
        text: I18n.tr(field.invalidMessage)
        color: Theme.brand
        font.family: Theme.font
        font.pixelSize: Theme.fMicro
    }
}
