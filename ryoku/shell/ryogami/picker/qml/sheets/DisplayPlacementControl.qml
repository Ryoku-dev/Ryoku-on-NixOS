import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    property string current: ""

    signal picked(string mode)

    implicitWidth: chips.implicitWidth
    implicitHeight: chips.implicitHeight

    ChoiceButtons {
        id: chips
        width: root.width > 0 ? root.width : implicitWidth
        value: root.current
        options: [
            { value: "fill", label: I18n.tr("Fill") },
            { value: "fit", label: I18n.tr("Fit") },
            { value: "stretch", label: I18n.tr("Stretch") },
            { value: "center", label: I18n.tr("Centre") },
            { value: "tile", label: I18n.tr("Tile") }
        ]
        onSelected: (v) => root.picked(v)
    }
}
