package doctor

import (
	"fmt"
	"os/exec"

	"ryoku-cli/internal/host"
	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

type qmkStatus struct {
	supported bool
	installed bool
}

const qmkPackage = "qmk-hid"

var (
	readQMKStatus        = probeQMKStatus
	qmkHardwareSupported = func() bool { return exec.Command("ryoku-hw-qmk").Run() == nil }
	qmkBinaryInstalled   = func() bool { _, err := exec.LookPath("qmk_hid"); return err == nil }
	qmkProviderAvailable = func() bool {
		app := host.Default()
		manager, err := app.PackageManager()
		if err != nil {
			return false
		}
		if manager == host.Pacman {
			return true
		}
		return app.Package([]string{"available", qmkPackage}) == host.ExitOK
	}
	qmkInstallAdvice = func() string { return host.Default().InstallAdvice(qmkPackage) }
	installQMK       = func() error {
		if code := host.Default().Package([]string{"install", "--aur", qmkPackage}); code != host.ExitOK {
			return fmt.Errorf("package install exited %d", code)
		}
		return nil
	}
	reloadQMKUdev = func() error {
		if err := sys.Sudo("udevadm", "control", "--reload"); err != nil {
			return err
		}
		return sys.Sudo("udevadm", "trigger", "--subsystem-match=hidraw")
	}
)

func probeQMKStatus() qmkStatus {
	st := qmkStatus{supported: qmkHardwareSupported()}
	if !st.supported {
		return st
	}
	st.installed = qmkBinaryInstalled()
	return st
}

// The udev reload applies the ACL to a board already connected during install.
func reconcileQMK(checkOnly bool) recResult {
	if sys.NixBackend() {
		return okRes("QMK HID support and udev policy are managed declaratively on NixOS")
	}

	st := readQMKStatus()
	if !st.supported {
		return okRes(i18n.T("this machine has no QMK/VIA keyboard for lighting"))
	}
	if st.installed {
		return okRes(i18n.T("QMK/VIA keyboard lighting provider is installed"))
	}
	if !qmkProviderAvailable() {
		return noteRes(i18n.T("QMK/VIA keyboard lighting provider is not packaged for this system")).
			withFix(qmkInstallAdvice())
	}
	if checkOnly {
		return wouldRes(i18n.T("QMK/VIA keyboard lighting provider is missing")).
			withFix(i18n.T("ryoku doctor installs qmk-hid so the keyboard follows the theme"))
	}
	if err := installQMK(); err != nil {
		return failRes(i18n.T("could not install the QMK lighting provider: %v"), err).
			withFix(qmkInstallAdvice())
	}
	_ = reloadQMKUdev()
	return fixedRes(i18n.T("installed qmk-hid; the QMK/VIA keyboard is available in Ryogami lighting settings"))
}
