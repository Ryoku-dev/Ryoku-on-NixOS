import QtQuick
import Quickshell
import inir
import inir.services
import inir.modules.common
import inir.modules.common.functions
import inir.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Virtual Keyboard")
    toggled: GlobalStates.oskOpen
    icon: toggled ? "keyboard_hide" : "keyboard"

    mainAction: () => {
        GlobalStates.oskOpen = !GlobalStates.oskOpen
    }

    tooltipText: Translation.tr("On-screen keyboard")
}
