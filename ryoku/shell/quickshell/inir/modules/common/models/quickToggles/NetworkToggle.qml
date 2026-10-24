import QtQuick
import Quickshell
import inir.services
import inir.modules.common
import inir.modules.common.functions
import inir.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Internet")
    statusText: Network.networkName
    tooltipText: Translation.tr("%1 | Right-click to configure").arg(Network.connectionTooltip())
    icon: Network.materialSymbol

    toggled: Network.wifiStatus !== "disabled"
    mainAction: () => Network.toggleWifi()
    hasMenu: true
    altAction: () => {
        AppLauncher.launchNetworkSettings(Network.ethernet)
    }
}
