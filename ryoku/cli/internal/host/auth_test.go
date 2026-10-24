package host

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFingerprintAuthStatusAndSet(t *testing.T) {
	dir := t.TempDir()
	pam := filepath.Join(dir, "pam.d")
	if err := os.MkdirAll(pam, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, target := range fingerprintPAMTargets {
		body := "# " + target + "\nauth required pam_unix.so\n"
		if err := os.WriteFile(filepath.Join(pam, target), []byte(body), 0o640); err != nil {
			t.Fatal(err)
		}
	}
	module := filepath.Join(dir, "pam_fprintd_grosshack.so")
	if err := os.WriteFile(module, nil, 0o644); err != nil {
		t.Fatal(err)
	}

	app, stdout, _ := testApp(&fakeRunner{}, nil)
	app.cfg.PAMDir = pam
	app.cfg.PAMModulePaths = []string{module}
	app.cfg.UID, app.cfg.UIDSet = 0, true
	if code := app.Auth([]string{"fingerprint", "set", "sudo", "on"}); code != ExitOK {
		t.Fatalf("enable exit = %d", code)
	}
	body, err := os.ReadFile(filepath.Join(pam, "sudo"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(body), fingerprintPAMLine+"\n") {
		t.Fatalf("enabled PAM = %q", body)
	}
	backup, err := os.ReadFile(filepath.Join(pam, "sudo") + ".ryoku-fp-bak")
	if err != nil || strings.Contains(string(backup), "pam_fprintd_grosshack") {
		t.Fatalf("backup = %q, err = %v", backup, err)
	}

	stdout.Reset()
	if code := app.Auth([]string{"fingerprint", "status"}); code != ExitOK {
		t.Fatalf("status exit = %d", code)
	}
	var status fingerprintStatus
	if err := json.Unmarshal(stdout.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if !status.Supported || !status.Targets["sudo"] || status.Targets["sddm"] {
		t.Fatalf("status = %#v", status)
	}

	stdout.Reset()
	if code := app.Auth([]string{"fingerprint", "set", "sudo", "off"}); code != ExitOK {
		t.Fatalf("disable exit = %d", code)
	}
	body, _ = os.ReadFile(filepath.Join(pam, "sudo"))
	if strings.Contains(string(body), "pam_fprintd_grosshack") {
		t.Fatalf("disabled PAM = %q", body)
	}
}

func TestFingerprintAuthSetEscalatesWholeOperation(t *testing.T) {
	runner := &fakeRunner{}
	app, _, _ := testApp(runner, nil)
	app.cfg.UID, app.cfg.UIDSet = 1000, true
	if code := app.Auth([]string{"fingerprint", "set", "polkit-1", "on"}); code != ExitOK {
		t.Fatalf("set exit = %d", code)
	}
	if got := argv(runner.commands[0]); got != "pkexec ryoku-host auth fingerprint set polkit-1 on" {
		t.Fatalf("escalation = %q", got)
	}
}

func TestFingerprintAuthStatusReportsMissingIntegration(t *testing.T) {
	app, stdout, _ := testApp(&fakeRunner{}, nil)
	app.cfg.PAMDir = t.TempDir()
	app.cfg.PAMModulePaths = []string{filepath.Join(t.TempDir(), "missing.so")}
	if code := app.Auth([]string{"fingerprint", "status"}); code != ExitOK {
		t.Fatalf("status exit = %d", code)
	}
	var status fingerprintStatus
	if err := json.Unmarshal(stdout.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if status.Supported || status.Reason == "" {
		t.Fatalf("status = %#v", status)
	}
}
