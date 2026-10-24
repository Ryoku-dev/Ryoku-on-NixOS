import QtQuick
import Quickshell
import inir
import inir.services
import inir.services.deferred
import inir.modules.common
import inir.modules.common.functions
import inir.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("EasyEffects")

    available: EasyEffects.available
    toggled: EasyEffects.active
    icon: "graphic_eq"

    Component.onCompleted: {
        EasyEffects.fetchActiveState()
    }

    mainAction: () => {
        EasyEffects.toggle()
    }

    altAction: () => {
        ShellExec.execFishOrBashOneLiner(
            "flatpak run com.github.wwmm.easyeffects; or easyeffects",
            "/usr/bin/flatpak run com.github.wwmm.easyeffects || /usr/bin/easyeffects"
        )
        GlobalStates.sidebarRightOpen = false
    }

    tooltipText: Translation.tr("EasyEffects | Right-click to configure")
}
