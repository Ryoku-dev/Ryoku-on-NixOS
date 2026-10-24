import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: root

    property string value: ""

    signal committed(string value)

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    readonly property bool _isSun: root.value === "sunrise" || root.value === "sunset"

    Column {
        id: col
        width: root.width > 0 ? root.width : implicitWidth
        spacing: Theme.spaceSm

        RowLayout {
            width: parent.width
            spacing: Theme.spaceSm

            TextField {
                id: field
                Layout.preferredWidth: 168 * Theme.scale
                variant: "field"
                placeholder: I18n.tr("HH:MM or sunset-30")
                text: root.value
                onCommitted: (t) => root.committed(t.trim())
                Connections {
                    target: root
                    function onValueChanged() { if (!field.editing) field.text = root.value }
                }
            }

            ChoiceButtons {
                Layout.alignment: Qt.AlignVCenter
                value: root._isSun ? root.value : ""
                options: [
                    { value: "sunrise", label: I18n.tr("Sunrise") },
                    { value: "sunset", label: I18n.tr("Sunset") }
                ]
                onSelected: (v) => root.committed(v)
            }
        }

        Text {
            width: parent.width
            text: I18n.tr("Use a clock time, sunrise, sunset, or add an offset such as sunset-30 or sunrise+45.")
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontTiny
            color: Theme.withAlpha(Theme.surfaceText, 0.42)
            lineHeight: 1.35
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }
    }
}
