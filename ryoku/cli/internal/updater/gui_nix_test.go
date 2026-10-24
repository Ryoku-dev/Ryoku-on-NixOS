package updater

import (
	"strings"
	"testing"
)

func containsArg(args []string, want string) bool {
	for _, arg := range args {
		if arg == want {
			return true
		}
	}
	return false
}

func TestNixGUIHostRunsOutsideShellService(t *testing.T) {
	t.Setenv("RYOKU_SYSTEMD_RUN", "/nix/store/test-systemd/bin/systemd-run")
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")
	t.Setenv("RYOKU_NIX_FLAKE", "/etc/nixos")
	t.Setenv("RYOKU_NIX_VERSION", "0.99.8-beta.20")
	t.Setenv("UNRELATED_SECRET", "do-not-forward")

	cmd := nixGUIHostCommand("/nix/store/test-ryoku/bin/ryoku", []string{"--force"})
	if cmd.Path != "/nix/store/test-systemd/bin/systemd-run" {
		t.Fatalf("runner = %q", cmd.Path)
	}

	args := cmd.Args[1:]
	for _, want := range []string{
		"--user",
		"--collect",
		"--service-type=exec",
		"--setenv=RYOKU_UPDATE_UI=hub",
		"--setenv=RYOKU_UPDATE_BACKEND=nix",
		"--setenv=RYOKU_NIX_FLAKE=/etc/nixos",
		"--setenv=RYOKU_NIX_VERSION=0.99.8-beta.20",
		"/nix/store/test-ryoku/bin/ryoku",
		"update",
		"--gui-host",
		"--force",
	} {
		if !containsArg(args, want) {
			t.Fatalf("missing %q in systemd-run args: %#v", want, args)
		}
	}

	for _, arg := range args {
		if strings.Contains(arg, "UNRELATED_SECRET") || strings.Contains(arg, "do-not-forward") {
			t.Fatalf("unrelated environment leaked into transient service args: %q", arg)
		}
	}
}
