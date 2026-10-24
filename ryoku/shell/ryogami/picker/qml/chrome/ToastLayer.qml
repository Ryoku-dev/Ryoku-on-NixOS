import QtQuick

// A new message replaces the last, so nothing stacks.
Item {
    id: layer

    required property PickerState state

    Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 * Theme.scale
    }

    function show(message, kind) {
        var k = kind || "info"
        toast.kind = k
        toast.glyph = k === "error" ? "\u{f06a}" : (k === "success" ? "\u{f058}" : "\u{f05a}")
        toast.open(message)
    }
}
