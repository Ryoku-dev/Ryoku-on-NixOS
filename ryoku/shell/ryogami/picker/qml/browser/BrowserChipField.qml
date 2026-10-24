import QtQuick
import Ryoku.Ui.Singletons

// A filter that takes typed text, such as a repository to add. Text the source refuses stays and turns the border red.
Rectangle {
    id: field

    property string placeholder: ""
    property string glyph: ""
    property bool invalid: false

    signal committed(string text)

    function clear() {
        input.text = ""
        field.invalid = false
    }
    function reject() { field.invalid = true }

    implicitHeight: input.implicitHeight + 8 * Theme.scale
    radius: Theme.radius
    color: Theme.withAlpha(Theme.surfaceText, 0.05)
    border.width: 1
    border.color: field.invalid ? Theme.withAlpha(Theme.tertiary, 0.8) : Theme.withAlpha(Theme.outline, 0.4)

    TextField {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 2 * Theme.scale
        anchors.rightMargin: 2 * Theme.scale
        variant: "ghost"
        glyph: field.glyph
        placeholder: field.placeholder
        onEdited: field.invalid = false
        onCommitted: function(text) {
            if (text.trim().length > 0)
                field.committed(text)
        }
    }
}
