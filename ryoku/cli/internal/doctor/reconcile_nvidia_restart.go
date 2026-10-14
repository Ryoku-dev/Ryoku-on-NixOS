package doctor

import (
	"os"

	"ryoku-cli/internal/updater"

	i18n "ryoku-i18n"
)

var (
	doctorNvidiaVersionFile = os.ReadFile
	doctorNvidiaModinfo     = updater.InstalledNvidiaModuleVersion
)

func nvidiaRestartStatus() updater.NvidiaRestartStatus {
	return updater.DetectNvidiaRestart(doctorNvidiaVersionFile, doctorNvidiaModinfo)
}

func planNvidiaRestart(status updater.NvidiaRestartStatus) recResult {
	if !status.Present {
		return okRes(i18n.T("no NVIDIA kernel module is loaded"))
	}
	if status.Installed == "" {
		return okRes(i18n.T("the installed NVIDIA driver version could not be compared with the loaded module"))
	}
	if !status.Pending {
		return okRes(i18n.T("the loaded and installed NVIDIA driver versions match (%s)"), status.Loaded)
	}
	return warnRes(updater.NvidiaRestartNotice(status)).
		withFix(i18n.T("restart the computer"))
}

func reconcileNvidiaRestart(_ bool) recResult {
	return planNvidiaRestart(nvidiaRestartStatus())
}

// A machine with no loaded NVIDIA module has no NVIDIA restart finding at all,
// rather than an irrelevant healthy row in doctor's JSON report.
func nvidiaRestartCheck() (reconciler, bool) {
	status := nvidiaRestartStatus()
	if !status.Present {
		return reconciler{}, false
	}
	return reconciler{
		name: i18n.T("NVIDIA driver restart"),
		run:  func(bool) recResult { return planNvidiaRestart(status) },
	}, true
}
