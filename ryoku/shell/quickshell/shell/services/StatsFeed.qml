pragma Singleton

import QtQuick
import Quickshell
import "../utils/menupoll.js" as MenuPoll

Singleton {
    id: root

    property var owners: []
    readonly property bool active: root.owners.length > 0
    function setActive(owner, on) {
        root.owners = MenuPoll.setOwnership(root.owners, owner, on);
    }

    readonly property int pollMs: 1500
    readonly property var monitor: Sysinfo.monitor

    property real gpuPct: monitor.gpuPercent
    property real gpuPowerW: monitor.gpuPowerWatts
    property real gpuTempC: monitor.gpuTemp
    property bool gpuAvailable: monitor.gpuAvailable || monitor.gpuTempAvailable

    property real downBps: monitor.networkRxBytesPerSec
    property real upBps: monitor.networkTxBytesPerSec
    property var netDownHist: monitor.networkRxHistory
    property var netUpHist: monitor.networkTxHistory

    property real diskUsedGiB: monitor.storageUsedGiB
    property real diskTotalGiB: monitor.storageTotalGiB
    property real fanRpm: monitor.fanRpm

    onActiveChanged: Sysinfo._setStatsActive(root.active)
    Component.onCompleted: Sysinfo._setStatsActive(root.active)
    Component.onDestruction: Sysinfo._setStatsActive(false)
}
