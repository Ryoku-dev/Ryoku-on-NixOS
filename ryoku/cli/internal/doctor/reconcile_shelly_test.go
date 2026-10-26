package doctor

import (
	"strings"
	"testing"

	"ryoku-cli/internal/host"
)

func stubShellyBackend(t *testing.T, shelly, backend, available bool, installCode int) *int {
	t.Helper()
	oldInstalled := shellyInstalled
	oldAvailable := shellyBackendAvailable
	oldInstall := shellyBackendInstall
	oldAdvice := shellyBackendAdvice
	t.Cleanup(func() {
		shellyInstalled = oldInstalled
		shellyBackendAvailable = oldAvailable
		shellyBackendInstall = oldInstall
		shellyBackendAdvice = oldAdvice
	})

	installed := map[string]bool{
		"shelly":             shelly,
		shellyFlatpakBackend: backend,
	}
	installs := 0
	shellyInstalled = func(name string) bool { return installed[name] }
	shellyBackendAvailable = func() bool { return available }
	shellyBackendInstall = func() int {
		installs++
		if installCode == host.ExitOK {
			installed[shellyFlatpakBackend] = true
		}
		return installCode
	}
	shellyBackendAdvice = func() string { return "install shelly-flatpak-backend" }
	return &installs
}

func TestShellyFlatpakReconcile(t *testing.T) {
	cases := []struct {
		name                       string
		shelly, backend, available bool
		checkOnly                  bool
		installCode, installs      int
		wantStatus                 recStatus
		detail                     string
	}{
		{name: "Shelly absent", available: true, wantStatus: recOK, detail: "not installed"},
		{name: "backend present", shelly: true, backend: true, available: true, wantStatus: recOK, detail: "is installed"},
		{name: "backend unavailable", shelly: true, wantStatus: recNote, detail: "not available"},
		{name: "check only", shelly: true, available: true, checkOnly: true, wantStatus: recWouldFix, detail: "install Shelly's Flatpak backend"},
		{name: "install succeeds", shelly: true, available: true, wantStatus: recFixed, installs: 1, detail: "searches and installs now work"},
		{name: "install fails", shelly: true, available: true, installCode: host.ExitFailure, wantStatus: recFailed, installs: 1, detail: "could not install"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			installs := stubShellyBackend(t, tc.shelly, tc.backend, tc.available, tc.installCode)
			got := reconcileShellyFlatpak(tc.checkOnly)
			if got.status != tc.wantStatus {
				t.Fatalf("status = %v, want %v: %s", got.status, tc.wantStatus, got.detail)
			}
			if *installs != tc.installs {
				t.Errorf("install calls = %d, want %d", *installs, tc.installs)
			}
			if !strings.Contains(got.detail, tc.detail) {
				t.Errorf("detail %q does not contain %q", got.detail, tc.detail)
			}
		})
	}
}
