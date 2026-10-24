import QtQuick
import Quickshell
import inir
import inir.services
import inir.modules.common
import inir.modules.common.functions
import inir.modules.common.widgets

QuickToggleModel {
    property bool auto: Nightlight.scheduled

    name: Translation.tr("Night Light")
    statusText: (auto ? Translation.tr("Auto, ") : "") + (toggled ? Translation.tr("Active") : Translation.tr("Inactive"))

    toggled: Nightlight.active
    icon: auto ? "night_sight_auto" : "bedtime"

    mainAction: () => {
        Nightlight.toggle()
    }
    hasMenu: true

    Component.onCompleted: {

    }

    tooltipText: Translation.tr("Night Light | Right-click to configure")
}
