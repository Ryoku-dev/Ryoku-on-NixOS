pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons

SettingCard {
    id: picker

    property string mode: "off"
    property bool interactive: true
    signal chose(string mode)

    width: parent ? parent.width : 0
    title: I18n.tr("MODE")
    kana: "景"
    collapsible: false

    function description(value) {
        if (value === "depth")
            return I18n.tr("Keep the wallpaper still and place widgets behind its cut-out subject.");
        if (value === "parallax")
            return I18n.tr("Let cut-out layers drift over an inpainted wallpaper backdrop.");
        if (value === "spatial")
            return I18n.tr("Turn the wallpaper into a 3D scene with a depth map.");
        return I18n.tr("Draw the wallpaper and desktop on one flat plane.");
    }

    SettingRow {
        width: parent.width
        label: I18n.tr("Wallpaper depth")
        desc: I18n.tr("Choose one mode for this wallpaper")
        block: true

        Column {
            width: parent.width
            spacing: Tokens.s2

            Seg {
                width: parent.width
                enabled: picker.interactive
                options: ["off", "depth", "parallax", "spatial"]
                labels: ({
                    off: I18n.tr("Plain"),
                    depth: I18n.tr("Depth"),
                    parallax: I18n.tr("Parallax"),
                    spatial: I18n.tr("Spatial")
                })
                current: picker.mode
                onChose: value => picker.chose(value)
            }

            Text {
                width: parent.width
                text: picker.description(picker.mode)
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }
        }
    }
}
