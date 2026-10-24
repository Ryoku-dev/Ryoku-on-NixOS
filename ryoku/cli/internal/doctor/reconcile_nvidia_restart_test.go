package doctor

import (
	"errors"
	"strings"
	"testing"

	"ryoku-cli/internal/updater"
)

func stubNvidiaRestartProbe(t *testing.T, loaded string, readErr error, installed string, modinfoErr error) {
	t.Helper()
	oldRead, oldModinfo := doctorNvidiaVersionFile, doctorNvidiaModinfo
	t.Cleanup(func() {
		doctorNvidiaVersionFile = oldRead
		doctorNvidiaModinfo = oldModinfo
	})
	doctorNvidiaVersionFile = func(path string) ([]byte, error) {
		if path != "/sys/module/nvidia/version" {
			t.Fatalf("version path = %q", path)
		}
		if readErr != nil {
			return nil, readErr
		}
		return []byte(loaded), nil
	}
	doctorNvidiaModinfo = func() (string, error) {
		return installed, modinfoErr
	}
}

func TestNvidiaRestartDetector(t *testing.T) {
	t.Run("matching versions", func(t *testing.T) {
		stubNvidiaRestartProbe(t, "615.78.08\n", nil, "615.78.08\n", nil)
		status := nvidiaRestartStatus()
		if !status.Present || status.Pending || status.Loaded != "615.78.08" || status.Installed != "615.78.08" {
			t.Fatalf("status = %+v, want present matching versions", status)
		}
	})

	t.Run("mismatched versions", func(t *testing.T) {
		stubNvidiaRestartProbe(t, "615.71.09\n", nil, "615.78.08\n", nil)
		status := nvidiaRestartStatus()
		if !status.Present || !status.Pending || status.Loaded != "615.71.09" || status.Installed != "615.78.08" {
			t.Fatalf("status = %+v, want pending restart", status)
		}
	})

	t.Run("no loaded module", func(t *testing.T) {
		stubNvidiaRestartProbe(t, "", errors.New("not found"), "", errors.New("modinfo must not run"))
		called := false
		doctorNvidiaModinfo = func() (string, error) {
			called = true
			return "615.78.08", nil
		}
		status := nvidiaRestartStatus()
		if status.Present || status.Pending || called {
			t.Fatalf("status = %+v, modinfo called=%v; want absent without a command", status, called)
		}
	})

	t.Run("modinfo failure", func(t *testing.T) {
		stubNvidiaRestartProbe(t, "615.71.09\n", nil, "", errors.New("modinfo failed"))
		status := nvidiaRestartStatus()
		if !status.Present || status.Pending || status.Installed != "" {
			t.Fatalf("status = %+v, want no false restart warning", status)
		}
	})
}

func TestReconcileNvidiaRestartWarnsWithoutRepair(t *testing.T) {
	stubNvidiaRestartProbe(t, "615.71.09\n", nil, "615.78.08\n", nil)
	r := reconcileNvidiaRestart(false)
	if r.status != recWarn {
		t.Fatalf("status = %s, want warn", r.status.label())
	}
	for _, want := range []string{"615.71.09", "615.78.08", "restart the computer before logging out", "black screen"} {
		if !strings.Contains(r.detail, want) {
			t.Errorf("detail %q missing %q", r.detail, want)
		}
	}
	if r.remedy != "restart the computer" {
		t.Errorf("remedy = %q, want restart the computer", r.remedy)
	}
}

func TestReconcileNvidiaRestartMatchesAndOmitsAbsentModule(t *testing.T) {
	stubNvidiaRestartProbe(t, "615.78.08\n", nil, "615.78.08\n", nil)
	if r := reconcileNvidiaRestart(false); r.status != recOK {
		t.Fatalf("matching versions = %s %q, want ok", r.status.label(), r.detail)
	}

	stubNvidiaRestartProbe(t, "", errors.New("not found"), "", nil)
	if _, ok := nvidiaRestartCheck(); ok {
		t.Fatal("a machine with no loaded NVIDIA module registered a finding")
	}
}

func TestUpdateResultCarriesNvidiaRestartNotice(t *testing.T) {
	status := updater.NvidiaRestartStatus{
		Present: true, Loaded: "615.71.09", Installed: "615.78.08", Pending: true,
	}
	notice := updater.NvidiaRestartNotice(status)
	for _, want := range []string{"615.71.09", "615.78.08", "restart the computer before logging out", "black screen"} {
		if !strings.Contains(notice, want) {
			t.Errorf("update notice %q missing %q", notice, want)
		}
	}
	status.Pending = false
	if notice := updater.NvidiaRestartNotice(status); notice != "" {
		t.Fatalf("matching update notice = %q, want empty", notice)
	}
}
