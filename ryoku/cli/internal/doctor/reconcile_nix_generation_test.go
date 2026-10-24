package doctor

import (
	"errors"
	"testing"

	"ryoku-cli/internal/sys"
)

func withNixGenerationSeams(t *testing.T) {
	t.Helper()
	oldRead := readNixIntegration
	oldExists := nixPathExists
	oldStore := nixStorePath
	oldExecutable := nixExecutable
	t.Cleanup(func() {
		readNixIntegration = oldRead
		nixPathExists = oldExists
		nixStorePath = oldStore
		nixExecutable = oldExecutable
	})
}

func healthyNixIntegration() sys.NixIntegration {
	return sys.NixIntegration{
		Schema:     1,
		Version:    "0.83.9-beta.20",
		Flake:      "/etc/nixos",
		Host:       "ryoku-test",
		ConfigBase: "/nix/store/config/share/ryoku/config",
		I18nDir:    "/nix/store/data/share/ryoku/i18n",
		Packages: []sys.NixPackage{
			{Name: "kitty", Path: "/nix/store/kitty"},
			{Name: "btop", Path: "/nix/store/btop"},
		},
	}
}

func TestNixGenerationProblemsHealthy(t *testing.T) {
	withNixGenerationSeams(t)
	nixPathExists = func(string) bool { return true }
	nixStorePath = func(string) bool { return true }
	nixExecutable = func(string) string { return "/run/current-system/sw/bin/tool" }
	if got := nixGenerationProblems(healthyNixIntegration()); len(got) != 0 {
		t.Fatalf("healthy generation reported problems: %v", got)
	}
}

func TestNixGenerationProblemsCatchMissingStoreAndBinary(t *testing.T) {
	withNixGenerationSeams(t)
	nixPathExists = func(path string) bool { return path != "/nix/store/btop" }
	nixStorePath = func(string) bool { return true }
	nixExecutable = func(name string) string {
		if name == "ryoku-wm-niri" {
			return ""
		}
		return "/run/current-system/sw/bin/" + name
	}
	problems := nixGenerationProblems(healthyNixIntegration())
	if len(problems) != 2 {
		t.Fatalf("problems = %v, want package + executable failures", problems)
	}
}

func TestNixRebuildRemedyIncludesHost(t *testing.T) {
	got := nixRebuildRemedy(healthyNixIntegration())
	want := "sudo nixos-rebuild switch --flake /etc/nixos#ryoku-test"
	if got != want {
		t.Fatalf("remedy = %q, want %q", got, want)
	}
}

func TestReconcileNixGenerationUnreadableManifest(t *testing.T) {
	withNixGenerationSeams(t)
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")
	readNixIntegration = func() (sys.NixIntegration, error) {
		return sys.NixIntegration{}, errors.New("missing")
	}
	res := reconcileNixGeneration(true)
	if res.status != recWarn {
		t.Fatalf("status = %v, want warning", res.status)
	}
	if res.remedy == "" {
		t.Fatal("missing NixOS rebuild remedy")
	}
}
