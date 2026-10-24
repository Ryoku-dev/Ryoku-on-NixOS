package sys

import (
	"os"
	"path/filepath"
	"testing"
)

func writeNixIntegration(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "nix-integration.json")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_NIX_INTEGRATION", path)
	return path
}

func TestNixBackend(t *testing.T) {
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")
	if !NixBackend() {
		t.Fatal("NixBackend() = false, want true")
	}

	t.Setenv("RYOKU_UPDATE_BACKEND", "pacman")
	if NixBackend() {
		t.Fatal("NixBackend() = true for non-Nix backend")
	}
}

func TestNixIntegrationDrivesPackageAndVersionQueries(t *testing.T) {
	writeNixIntegration(t, `{
  "schema": 1,
  "version": "0.83.9-beta.20",
  "configBase": "/nix/store/abc-ryoku-desktop-data/share/ryoku/config",
  "packages": [
    {"name": "kitty", "path": "/nix/store/one-kitty-0.40"},
    {"name": "ryoku-shell", "path": "/nix/store/two-ryoku-shell-unstable"}
  ]
}`)
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")

	if !PkgInstalled("kitty") {
		t.Fatal("kitty should be present in the Nix generation manifest")
	}
	if PkgInstalled("definitely-absent") {
		t.Fatal("unknown package reported installed")
	}
	if got := NixPackagePath("ryoku-shell"); got != "/nix/store/two-ryoku-shell-unstable" {
		t.Fatalf("NixPackagePath = %q", got)
	}
	if got := InstalledVersion(); got != "0.83.9-beta.20" {
		t.Fatalf("InstalledVersion = %q", got)
	}
}

func TestNixBackendFallsBackToIntegrationManifest(t *testing.T) {
	writeNixIntegration(t, `{"schema":1,"packages":[]}`)
	t.Setenv("RYOKU_UPDATE_BACKEND", "")
	if !NixBackend() {
		t.Fatal("integration manifest should identify a NixOS integration")
	}
}

func TestNixDataDirsIncludeActiveProfiles(t *testing.T) {
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")
	t.Setenv("XDG_DATA_DIRS", "")
	t.Setenv("HOME", "/home/tester")
	t.Setenv("USER", "tester")
	got := DataDirs()
	want := map[string]bool{
		"/run/current-system/sw/share":        false,
		"/etc/profiles/per-user/tester/share": false,
		"/home/tester/.nix-profile/share":     false,
	}
	for _, dir := range got {
		if _, ok := want[dir]; ok {
			want[dir] = true
		}
	}
	for dir, seen := range want {
		if !seen {
			t.Errorf("DataDirs missing %s: %v", dir, got)
		}
	}
}
