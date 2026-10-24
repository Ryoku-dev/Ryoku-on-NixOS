import QtQuick
import Quickshell
import inir
import inir.services
import inir.modules.common
import inir.modules.common.functions
import inir.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Audio input")
    statusText: toggled ? Translation.tr("Enabled") : Translation.tr("Muted")
    toggled: !Audio.micMuted
    icon: Audio.micMuted ? "mic_off" : "mic"
    mainAction: () => {
        Audio.toggleMicMute()
    }
    hasMenu: true

    tooltipText: Translation.tr("Audio input | Right-click for volume mixer & device selector")
}
