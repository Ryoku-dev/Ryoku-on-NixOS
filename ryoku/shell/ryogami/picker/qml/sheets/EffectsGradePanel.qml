import QtQuick
import Ryoku.Ui.Singletons

// Sliders fire changed only on release so the owner renders on let-go; toggles fire at once.
Item {
    id: panel

    property real brightness: 0
    property real contrast: 0
    property real saturation: 0
    property real warmth: 0
    property bool vignette: false
    property bool negate: false

    signal changed()
    signal gradeReset()

    function reset() {
        panel.brightness = 0
        panel.contrast = 0
        panel.saturation = 0
        panel.warmth = 0
        panel.vignette = false
        panel.negate = false
        panel.gradeReset()
    }

    implicitWidth: 320 * Theme.scale
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: panel.width
        spacing: 14 * Theme.scale

        Repeater {
            model: [
                { label: I18n.tr("Brightness"), prop: "brightness", from: -50, to: 50 },
                { label: I18n.tr("Contrast"),   prop: "contrast",   from: -50, to: 50 },
                { label: I18n.tr("Saturation"), prop: "saturation", from: -100, to: 100 },
                { label: I18n.tr("Warmth"),     prop: "warmth",     from: -100, to: 100 }
            ]

            delegate: Column {
                id: row
                required property var modelData
                width: col.width
                spacing: 8 * Theme.scale

                FolioRule { width: parent.width; alpha: 0.38 }

                Row {
                    width: parent.width
                    spacing: 8 * Theme.scale
                    Text {
                        width: parent.width - valueText.width - parent.spacing
                        text: row.modelData.label
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontBase
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                    Text {
                        id: valueText
                        text: String(Math.round(slider.value))
                        font.family: Theme.display
                        font.pixelSize: Theme.fontBody
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                    }
                }

                FolioSlider {
                    id: slider
                    width: parent.width
                    from: row.modelData.from
                    to: row.modelData.to
                    step: 1
                    Component.onCompleted: value = panel[row.modelData.prop]
                    onMoved: (v) => panel[row.modelData.prop] = Math.round(v)
                    onReleased: (v) => { panel[row.modelData.prop] = Math.round(v); panel.changed() }
                }
                Connections {
                    target: panel
                    function onGradeReset() {
                        if (!slider.dragging)
                            slider.value = panel[row.modelData.prop]
                    }
                }
            }
        }

        Column {
            width: col.width
            spacing: 8 * Theme.scale
            FolioRule { width: parent.width; alpha: 0.38 }
            Row {
                width: parent.width
                spacing: 8 * Theme.scale
                Text {
                    width: parent.width - vignetteToggle.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Vignette")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontBase
                    color: Theme.surfaceText
                    renderType: Text.NativeRendering
                }
                Switch {
                    id: vignetteToggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: panel.vignette
                    onToggled: { panel.vignette = checked; panel.changed() }
                }
            }
        }

        Column {
            width: col.width
            spacing: 8 * Theme.scale
            FolioRule { width: parent.width; alpha: 0.38 }
            Row {
                width: parent.width
                spacing: 8 * Theme.scale
                Text {
                    width: parent.width - negateToggle.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Negate")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontBase
                    color: Theme.surfaceText
                    renderType: Text.NativeRendering
                }
                Switch {
                    id: negateToggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: panel.negate
                    onToggled: { panel.negate = checked; panel.changed() }
                }
            }
        }
    }
}
