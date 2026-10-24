import QtQuick
import Ryoku.Ui.Singletons

FixedButton {
    id: keybind

    // Empty means unbound.
    property string binding: ""
    property bool capturing: false

    signal captureRequested()

    active: keybind.capturing
    label: keybind.capturing
        ? I18n.tr("Press keys…")
        : (keybind.binding.length > 0 ? keybind.binding : I18n.tr("Unbound"))

    onTriggered: keybind.captureRequested()
}
