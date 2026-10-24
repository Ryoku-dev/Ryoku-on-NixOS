import QtQuick
import QtQuick.Layouts
import inir.modules.common

RippleButton {
    Layout.fillHeight: true
    buttonRadius: Appearance.regaliaEverywhere ? Appearance.regalia.roundSmall
        : Appearance.zzzEverywhere ? Appearance.zzz.controlRadius
        : Appearance.editorialEverywhere ? Appearance.rounding.small : Appearance.rounding.full
}
