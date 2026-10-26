package doctor

import (
	"ryoku-cli/internal/host"

	i18n "ryoku-i18n"
)

const shellyFlatpakBackend = "shelly-flatpak-backend"

var (
	shellyInstalled = func(name string) bool {
		return doctorPackageInstalled(name)
	}
	shellyBackendAvailable = func() bool {
		return doctorPackageAvailability(shellyFlatpakBackend) == host.ExitOK
	}
	shellyBackendInstall = func() int {
		return doctorPackageInstall(shellyFlatpakBackend)
	}
	shellyBackendAdvice = func() string {
		return doctorInstallAdvice(shellyFlatpakBackend)
	}
)

func reconcileShellyFlatpak(checkOnly bool) recResult {
	if !shellyInstalled("shelly") {
		return okRes(i18n.T("Shelly is not installed; its Flatpak backend is not needed"))
	}
	if shellyInstalled(shellyFlatpakBackend) {
		return okRes(i18n.T("Shelly's Flatpak backend is installed"))
	}
	if !shellyBackendAvailable() {
		return noteRes(i18n.T("Shelly's Flatpak backend is not available from this system's repositories")).
			withFix(shellyBackendAdvice())
	}
	if checkOnly {
		return wouldRes(i18n.T("install Shelly's Flatpak backend so its Flatpak pages work")).
			withFix(i18n.T("ryoku doctor installs shelly-flatpak-backend"))
	}
	if code := shellyBackendInstall(); code != host.ExitOK {
		return failRes(i18n.T("could not install Shelly's Flatpak backend (exit %d)"), code).
			withFix(shellyBackendAdvice())
	}
	if !shellyInstalled(shellyFlatpakBackend) {
		return failRes(i18n.T("Shelly's Flatpak backend was installed but is still not detected")).
			withFix(shellyBackendAdvice())
	}
	return fixedRes(i18n.T("installed Shelly's Flatpak backend; its Flatpak searches and installs now work"))
}
