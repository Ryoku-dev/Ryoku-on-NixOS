import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: row

    property var control: ({})
    property var state
    property var options
    property real reveal: 1

    implicitHeight: col.implicitHeight

    readonly property var _weights: [
        { key: "motion.fastMs", label: I18n.tr("Fast") },
        { key: "motion.standardMs", label: I18n.tr("Standard") },
        { key: "motion.slowMs", label: I18n.tr("Slow") }
    ]

    Column {
        id: col
        width: row.width
        spacing: 6 * Theme.scale

        Text {
            width: parent.width
            text: row.control.label ? row.control.label : I18n.tr("Motion weights")
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontField
            color: Theme.withAlpha(Theme.surfaceText, row.reveal)
            renderType: Text.NativeRendering
        }
        Text {
            width: parent.width
            visible: !!row.control.help && row.control.help.length > 0
            text: row.control.help ? row.control.help : ""
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontBase
            color: Theme.withAlpha(Theme.surfaceText, 0.56 * row.reveal)
            lineHeight: 1.38
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        Flow {
            width: parent.width
            spacing: 18 * Theme.scale

            Repeater {
                model: row._weights

                delegate: Row {
                    id: weight
                    required property var modelData
                    spacing: 8 * Theme.scale

                    SettingValue { id: wv; key: weight.modelData.key }

                    Column {
                        spacing: 3 * Theme.scale
                        Text {
                            text: weight.modelData.label
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontBase
                            color: Theme.withAlpha(Theme.surfaceText, 0.7 * row.reveal)
                            renderType: Text.NativeRendering
                        }
                        Row {
                            spacing: 6 * Theme.scale
                            NumberField {
                                anchors.verticalCenter: parent.verticalCenter
                                enabled: row.enabled
                                unit: row.control.unit ? row.control.unit : I18n.tr("ms")
                                min: (wv.spec && wv.spec.min !== undefined && wv.spec.min !== null) ? Number(wv.spec.min) : NaN
                                max: (wv.spec && wv.spec.max !== undefined && wv.spec.max !== null) ? Number(wv.spec.max) : NaN
                                value: (wv.value === undefined || wv.value === null) ? null : Number(wv.value)
                                onCommitted: (v) => wv.set(v)
                            }
                            ResetChip {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !wv.isDefault && row.enabled
                                onTriggered: wv.reset()
                            }
                        }
                    }
                }
            }
        }
    }
}
