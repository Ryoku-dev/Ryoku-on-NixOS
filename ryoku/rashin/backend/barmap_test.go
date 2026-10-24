package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// barTestEnv points the catalogue reader at a temp checkout carrying widgets.json
// and neutralises PATH so the section never queries a live daemon.
func barTestEnv(t *testing.T, catalogue string) {
	t.Helper()
	h := t.TempDir()
	t.Setenv("HOME", h)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(h, ".config")) // no live config
	t.Setenv("XDG_STATE_HOME", filepath.Join(h, ".local", "state"))
	// no packaged base: on an installed box /usr/share/ryoku/config would
	// shadow the temp catalogue (and defeat the missing-catalogue case).
	t.Setenv("RYOKU_CONFIG_BASE", filepath.Join(h, "usr-share-absent"))
	t.Setenv("PATH", "") // loadPluginWidgets finds no ryoku-shell
	if catalogue == "" {
		t.Setenv("RYOKU_RASHIN_REPO", "")
		return
	}
	repo := t.TempDir()
	dir := filepath.Join(repo, "ryoku", "shell", "quickshell", "shell",
		"modules", "bar", "barstyles", "qsbar", "core")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "widgets.json"), []byte(catalogue), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_RASHIN_REPO", repo)
}

func TestBarSectionFromCatalogueFile(t *testing.T) {
	barTestEnv(t, `[
	  {"id":"launcher","gid":"G1","label":"Launcher","gloss":"kido","settings":[{"key":"launcherLogoMode","type":"choice"}]},
	  {"id":"status","gid":"G3","label":"Status","visKey":"status","desc":"x"},
	  {"id":"clock","gid":"G8","label":"Clock"}
	]`)
	body := barSectionBody()
	for _, want := range []string{
		vaultBarFenceBegin,
		vaultBarFenceEnd,
		"## Bar and dock",
		"| id | label | visibility key | settings keys |",
		"| launcher | Launcher | (always) | launcherLogoMode |",
		"| status | Status | status | (none) |",
		"| clock | Clock | (always) | (none) |",
		"ryoku-shell bar move clock --section right",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("bar section missing %q\n---\n%s", want, body)
		}
	}
}

func TestBarSectionDegradesWithoutCatalogue(t *testing.T) {
	barTestEnv(t, "")
	body := barSectionBody()
	if !strings.Contains(body, vaultBarFenceBegin) || !strings.Contains(body, "## Bar and dock") {
		t.Fatal("section should still render its heading and fence")
	}
	if !strings.Contains(body, "widget catalogue not found") {
		t.Fatalf("section should note the missing catalogue:\n%s", body)
	}
}

func TestSettingKeys(t *testing.T) {
	if got := settingKeys(nil); got != "(none)" {
		t.Fatalf("nil -> %q", got)
	}
	if got := settingKeys([]barSetting{{Key: "a"}, {Key: ""}, {Key: "b"}}); got != "a, b" {
		t.Fatalf("keys -> %q", got)
	}
}
