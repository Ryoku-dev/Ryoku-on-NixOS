package host

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNixPhoneNeverMutatesHost(t *testing.T) {
	for _, enabled := range []bool{false, true} {
		dir := t.TempDir()
		path := filepath.Join(dir, "phone.json")
		body, _ := json.Marshal(map[string]bool{"enabled": enabled, "webcam": false})
		if err := os.WriteFile(path, body, 0600); err != nil {
			t.Fatal(err)
		}
		for _, action := range []string{"status", "enable", "disable", "plan-enable", "plan-disable"} {
			runner := &fakeRunner{paths: map[string]bool{"pacman": true, "modprobe": true}}
			app, stdout, stderr := testApp(runner, map[string]string{
				"RYOKU_HOST_PLATFORM": "nixos", "RYOKU_NIX_PHONE_CONFIG": path,
			})
			code := app.Execute([]string{"phone", action})
			if action == "enable" && !enabled {
				if code == ExitOK || !strings.Contains(stderr.String(), "programs.ryoku.phone.enable") {
					t.Fatalf("disabled enable: code=%d error=%s", code, stderr)
				}
			} else if code != ExitOK {
				t.Fatalf("%s: %s", action, stderr)
			}
			if len(runner.commands) != 0 {
				t.Fatalf("%s ran host commands: %v", action, runner.commands)
			}
			if action == "status" {
				var status phoneStatus
				if err := json.Unmarshal(stdout.Bytes(), &status); err != nil {
					t.Fatal(err)
				}
				if status.Manager != "nix" || status.Installed != enabled || status.Supported != enabled {
					t.Fatalf("unexpected status: %+v", status)
				}
			}
			got, err := os.ReadFile(path)
			if err != nil || string(got) != string(body) {
				t.Fatalf("%s changed generation config", action)
			}
		}
	}
}

func TestNixPhoneMissingConfigDoesNotFallBackToPackages(t *testing.T) {
	runner := &fakeRunner{paths: map[string]bool{"pacman": true}}
	app, stdout, stderr := testApp(runner, map[string]string{
		"RYOKU_HOST_PLATFORM": "nixos", "RYOKU_NIX_PHONE_CONFIG": filepath.Join(t.TempDir(), "missing"),
	})
	if code := app.Execute([]string{"phone", "status"}); code != ExitOK {
		t.Fatal(stderr.String())
	}
	var status phoneStatus
	if err := json.Unmarshal(stdout.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if status.Supported || status.Installed || len(runner.commands) != 0 {
		t.Fatalf("unexpected fallback: %+v", status)
	}
}
