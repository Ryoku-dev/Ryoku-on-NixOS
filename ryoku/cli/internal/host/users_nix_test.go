package host

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func addCarol(t *testing.T, env map[string]string) (*fakeRunner, int, string) {
	t.Helper()
	for key, value := range env {
		t.Setenv(key, value)
	}
	passwdPath, groupPath := writeUsersFixtures(t)
	runner := &fakeRunner{}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_INIT": "systemd"})
	app.cfg.PasswdPath, app.cfg.GroupPath = passwdPath, groupPath
	app.cfg.HomeRoot = t.TempDir()
	app.cfg.Stdin = strings.NewReader("correct horse battery staple\n")
	app.cfg.UID, app.cfg.UIDSet = 0, true
	code := app.Users([]string{"add", "carol", "--full-name", "Carol", "--role", "standard"})
	return runner, code, stdout.String()
}

func useraddArgs(runner *fakeRunner) string {
	for _, command := range runner.commands {
		if command.Name == "useradd" {
			return strings.Join(command.Args, " ")
		}
	}
	return ""
}

func nixIntegration(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "nix-integration.json")
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestUsersAddGivesBashOutsideNixOS(t *testing.T) {
	runner, code, out := addCarol(t, map[string]string{"RYOKU_UPDATE_BACKEND": "pacman"})
	if code != ExitOK {
		t.Fatalf("add exit = %d, output = %s", code, out)
	}
	if args := useraddArgs(runner); !strings.Contains(args, "--shell /bin/bash") {
		t.Fatalf("useradd args = %q", args)
	}
}

// NixOS has no /bin/bash: a login shell there would leave the account unable
// to sign in, so useradd falls back to the shell NixOS configured.
func TestUsersAddLeavesTheShellToNixOS(t *testing.T) {
	runner, code, out := addCarol(t, map[string]string{
		"RYOKU_UPDATE_BACKEND":  "nix",
		"RYOKU_NIX_INTEGRATION": nixIntegration(t, `{"mutableUsers":true}`),
	})
	if code != ExitOK {
		t.Fatalf("add exit = %d, output = %s", code, out)
	}
	args := useraddArgs(runner)
	if args == "" || strings.Contains(args, "--shell") {
		t.Fatalf("useradd args = %q", args)
	}
}

func TestUsersRefusesChangesNixOSWouldRevert(t *testing.T) {
	runner, code, out := addCarol(t, map[string]string{
		"RYOKU_UPDATE_BACKEND":  "nix",
		"RYOKU_NIX_INTEGRATION": nixIntegration(t, `{"mutableUsers":false}`),
	})
	if code != ExitFailure || !strings.Contains(out, "users.mutableUsers = false") {
		t.Fatalf("add exit = %d, output = %s", code, out)
	}
	if args := useraddArgs(runner); args != "" {
		t.Fatalf("useradd ran on a declared-accounts system: %q", args)
	}
}
