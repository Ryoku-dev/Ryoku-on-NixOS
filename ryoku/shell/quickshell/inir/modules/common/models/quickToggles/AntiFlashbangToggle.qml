import QtQuick
import inir.services
import inir.modules.common
import inir.modules.common.functions
import inir.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Anti-flashbang")
    tooltipText: Translation.tr("Anti-flashbang")
    icon: "flash_off"
    toggled: Config.options?.light?.antiFlashbang?.enable ?? false

    mainAction: () => {
        const current = Config.options?.light?.antiFlashbang?.enable ?? false
        Config.setNestedValue("light.antiFlashbang.enable", !current)
    }
    hasMenu: true
}
