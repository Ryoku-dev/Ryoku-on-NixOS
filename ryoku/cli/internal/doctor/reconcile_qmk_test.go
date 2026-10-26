package doctor

import "testing"

func TestProbeQMKStatusUsesQMKHIDBinary(t *testing.T) {
	oldHardware, oldBinary := qmkHardwareSupported, qmkBinaryInstalled
	t.Cleanup(func() { qmkHardwareSupported, qmkBinaryInstalled = oldHardware, oldBinary })
	qmkHardwareSupported = func() bool { return true }
	qmkBinaryInstalled = func() bool { return true }

	if got := probeQMKStatus(); !got.supported || !got.installed {
		t.Fatalf("status = %+v, want supported with qmk_hid binary installed", got)
	}
	qmkBinaryInstalled = func() bool { return false }
	if got := probeQMKStatus(); got.installed {
		t.Fatalf("status = %+v, want missing without qmk_hid binary", got)
	}
	if qmkPackage != "qmk-hid" {
		t.Fatalf("package = %q, want AUR package qmk-hid", qmkPackage)
	}
}

func TestReconcileQMKIgnoresOtherHardware(t *testing.T) {
	withQMKTestState(t, qmkStatus{})
	if got := reconcileQMK(false); got.status != recOK {
		t.Fatalf("status = %v, detail = %s", got.status, got.detail)
	}
}

func TestReconcileQMKInstallsWhenBoardPresent(t *testing.T) {
	withQMKTestState(t, qmkStatus{supported: true})
	var installed, reloaded bool
	oldInstall, oldReload := installQMK, reloadQMKUdev
	installQMK = func() error { installed = true; return nil }
	reloadQMKUdev = func() error { reloaded = true; return nil }
	defer func() { installQMK, reloadQMKUdev = oldInstall, oldReload }()

	got := reconcileQMK(false)
	if got.status != recFixed || !installed || !reloaded {
		t.Fatalf("result = %+v, installed=%v reloaded=%v", got, installed, reloaded)
	}
}

func TestReconcileQMKCheckOnlyAndAlreadyInstalled(t *testing.T) {
	withQMKTestState(t, qmkStatus{supported: true})
	if got := reconcileQMK(true); got.status != recWouldFix {
		t.Fatalf("check status = %v, detail = %s", got.status, got.detail)
	}

	withQMKTestState(t, qmkStatus{supported: true, installed: true})
	if got := reconcileQMK(false); got.status != recOK {
		t.Fatalf("installed status = %v, detail = %s", got.status, got.detail)
	}
}

func TestReconcileQMKNotesUnavailableProvider(t *testing.T) {
	withQMKTestState(t, qmkStatus{supported: true})
	qmkProviderAvailable = func() bool { return false }
	qmkInstallAdvice = func() string { return "qmk-hid is not packaged for this system" }
	oldInstall := installQMK
	installQMK = func() error { t.Fatal("unavailable provider was installed"); return nil }
	t.Cleanup(func() { installQMK = oldInstall })

	got := reconcileQMK(false)
	if got.status != recNote || got.remedy != "qmk-hid is not packaged for this system" {
		t.Fatalf("result = %#v, want unavailable note with host advice", got)
	}
}

func withQMKTestState(t *testing.T, state qmkStatus) {
	t.Helper()
	oldStatus := readQMKStatus
	oldAvailable, oldAdvice := qmkProviderAvailable, qmkInstallAdvice
	readQMKStatus = func() qmkStatus { return state }
	qmkProviderAvailable = func() bool { return true }
	qmkInstallAdvice = func() string { return "yay -S qmk-hid" }
	t.Cleanup(func() {
		readQMKStatus = oldStatus
		qmkProviderAvailable, qmkInstallAdvice = oldAvailable, oldAdvice
	})
}
