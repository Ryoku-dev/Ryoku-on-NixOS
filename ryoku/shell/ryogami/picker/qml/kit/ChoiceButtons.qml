import QtQuick

// Chips and dropdowns draw the same way, so mode only records the caller's intent.
Item {
    id: choice

    property var options: []
    property var value: undefined
    property string mode: "chips"
    property bool showStrip: false
    property real gap: 7

    signal selected(var value)

    implicitWidth: flow.implicitWidth
    implicitHeight: flow.implicitHeight

    function _eq(a, b) { return a !== undefined && b !== undefined && a === b }

    Flow {
        id: flow
        width: choice.width > 0 ? choice.width : implicitWidth
        spacing: choice.gap * Theme.scale

        Repeater {
            model: choice.options

            delegate: Column {
                id: chip
                required property var modelData
                spacing: 0

                FixedButton {
                    id: chipButton
                    label: chip.modelData.label !== undefined ? chip.modelData.label : String(chip.modelData.value)
                    glyph: chip.modelData.glyph !== undefined ? chip.modelData.glyph : ""
                    active: choice._eq(chip.modelData.value, choice.value)
                    enabled: chip.modelData.enabled !== undefined ? chip.modelData.enabled : true
                    onTriggered: choice.selected(chip.modelData.value)
                }

                Rectangle {
                    visible: choice.showStrip && chip.modelData.strip !== undefined
                    width: chipButton.width
                    height: 10 * Theme.scale
                    color: chip.modelData.strip !== undefined ? chip.modelData.strip : "transparent"
                }
            }
        }
    }
}
