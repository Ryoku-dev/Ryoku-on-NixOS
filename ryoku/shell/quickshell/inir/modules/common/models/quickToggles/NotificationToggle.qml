import QtQuick
import Quickshell
import inir
import inir.services
import inir.modules.common
import inir.modules.common.functions
import inir.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Notifications")
    statusText: toggled ? Translation.tr("Show") : Translation.tr("Silent")
    toggled: !Notifications.silent
    icon: toggled ? "notifications_active" : "notifications_paused"

    mainAction: () => {
        Notifications.silent = !Notifications.silent;
    }

    tooltipText: Translation.tr("Show notifications")
}
