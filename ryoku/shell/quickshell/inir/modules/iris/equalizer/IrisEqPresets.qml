pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import shell.services as Ryoku
import inir.services
import inir.modules.common
import inir.modules.common.widgets
import inir.modules.iris.components
import inir.modules.iris.style

ColumnLayout {
    id: root

    spacing: Math.round(8 * IrisStyle.density)

    IrisText {
        text: Translation.tr("Presets")
        role: IrisText.Eyebrow
    }

    Flow {
        id: chipFlow
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        spacing: Math.round(6 * IrisStyle.density)

        Repeater {
            model: Ryoku.Equalizer.presets

            IrisChip {
                id: chip
                required property string modelData

                label: Ryoku.Equalizer.presetLabel(chip.modelData)
                glyph: "equalizer"
                selected: Ryoku.Equalizer.preset === chip.modelData
                scale: chip.selected ? 1 : chipHover.hovered ? 1.03 : 1
                onClicked: Ryoku.Equalizer.applyPreset(chip.modelData)

                HoverHandler { id: chipHover }
                Behavior on scale {
                    NumberAnimation {
                        duration: IrisStyle.duration(120)
                        easing.type: IrisStyle.feedbackEasing
                    }
                }
            }
        }
    }
}
