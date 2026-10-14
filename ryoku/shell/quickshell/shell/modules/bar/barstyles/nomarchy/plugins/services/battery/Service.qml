import QtQuick 6.11
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import shell.services as Ryoku

Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string pendingPowerSource: ""
  readonly property string activePowerProfile: Ryoku.PowerProfiles.profile
  readonly property bool powerSaverOnBattery: UPower.onBattery && activePowerProfile === "power-saver"

  function applyPowerProfile() {
    pendingPowerSource = UPower.onBattery ? "battery" : "ac"
    if (!powerProfileProcess.running) runPendingPowerProfile()
  }

  function runPendingPowerProfile() {
    powerProfileProcess.command = ["omarchy-powerprofiles-set", pendingPowerSource]
    pendingPowerSource = ""
    powerProfileProcess.running = true
  }

  Process {
    id: powerProfileProcess
    onExited: if (root.pendingPowerSource !== "") root.runPendingPowerProfile()
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.applyPowerProfile()
    }
  }
}
