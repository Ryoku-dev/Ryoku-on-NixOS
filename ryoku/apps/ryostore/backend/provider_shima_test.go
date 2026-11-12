package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func shimaStoreTest(t *testing.T) {
	t.Helper()
	root := t.TempDir()
	t.Setenv("XDG_STATE_HOME", filepath.Join(root, "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
}

func TestShimaRemovalPreservesSettingsAndUnrelatedFiles(t *testing.T) {
	shimaStoreTest(t)
	profile := shimaProfile()
	os.MkdirAll(filepath.Dir(profile), 0700)
	target := t.TempDir()
	os.Symlink(target, profile)
	os.Symlink(target, filepath.Join(filepath.Dir(profile), "profile-1-link"))
	unrelated := filepath.Join(filepath.Dir(profile), "keep")
	os.WriteFile(unrelated, []byte("keep"), 0600)
	config := defaultShellConfigPath()
	os.MkdirAll(filepath.Dir(config), 0700)
	os.WriteFile(config, []byte(`{"barStyle":"iris","unrelated":42,"inir":{"keep":true}}`), 0600)
	if err := removeShima(context.Background()); err != nil {
		t.Fatal(err)
	}
	if readBarStyleSelection(config) != "sumi" {
		t.Fatal("active runtime not moved to fallback")
	}
	if _, err := os.Lstat(profile); !os.IsNotExist(err) {
		t.Fatal("profile remains")
	}
	if _, err := os.Stat(unrelated); err != nil {
		t.Fatal("unrelated file removed")
	}
	state, _ := readConfigState(config)
	if state["unrelated"] != float64(42) || state["inir"] == nil {
		t.Fatal("settings lost")
	}
}

func TestShimaRemovalPreservesNewerSelection(t *testing.T) {
	shimaStoreTest(t)
	profile := shimaProfile()
	os.MkdirAll(filepath.Dir(profile), 0700)
	os.Symlink(t.TempDir(), profile)
	config := defaultShellConfigPath()
	os.MkdirAll(filepath.Dir(config), 0700)
	os.WriteFile(config, []byte(`{"barStyle":"python"}`), 0600)
	if err := removeShima(context.Background()); err != nil {
		t.Fatal(err)
	}
	if readBarStyleSelection(config) != "python" {
		t.Fatal("newer selection lost")
	}
}

func TestShimaBuildFailureKeepsInstalledGeneration(t *testing.T) {
	shimaStoreTest(t)
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Fatal(err)
	}
	bin := t.TempDir()
	os.WriteFile(filepath.Join(bin, "nix"), []byte("#!"+bash+"\nexit 9\n"), 0700)
	t.Setenv("PATH", bin)
	t.Setenv("RYOKU_SHIMA_FLAKE", "/nix/store/test-shima-install-source")
	profile := shimaProfile()
	os.MkdirAll(filepath.Dir(profile), 0700)
	target := t.TempDir()
	os.Symlink(target, profile)
	if err := installShima(context.Background()); err == nil {
		t.Fatal("failed build accepted")
	}
	actual, _ := os.Readlink(profile)
	if actual != target {
		t.Fatal("failed build replaced working generation")
	}
}

func TestShimaUnownedRemovalRejected(t *testing.T) {
	shimaStoreTest(t)
	if err := removeShima(context.Background()); err == nil {
		t.Fatal("unowned removal accepted")
	}
}

func TestShimaPreviewAndContributors(t *testing.T) {
	shimaStoreTest(t)
	preview := filepath.Join(t.TempDir(), "shima-preview.webp")
	if err := os.WriteFile(preview, []byte("preview"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_SHIMA_PREVIEW", preview)
	item := shimaItem()
	if item.ID != "iris" || item.Name != "Shima" {
		t.Fatalf("existing Shima listing was replaced: %+v", item)
	}
	if item.Author != "snowarch & aethctl" {
		t.Fatalf("Shima credits omitted original upstream author or Ryoku integrator: %s", item.Author)
	}
	if item.Art != "file://"+preview {
		t.Fatalf("unexpected preview art: %q", item.Art)
	}
	if item.Upstream != "https://github.com/snowarch/iNiR" {
		t.Fatalf("upstream attribution lost: %q", item.Upstream)
	}

	t.Setenv("RYOKU_SHIMA_PREVIEW", filepath.Join(t.TempDir(), "missing.webp"))
	if art := shimaItem().Art; art != "" {
		t.Fatalf("missing preview file should not create a broken image URL: %q", art)
	}
}

func TestShimaUsesSingleExistingBarStyleEntry(t *testing.T) {
	shimaStoreTest(t)
	items := builtinBarStyles()
	count := 0
	for _, item := range items {
		if item.ID != "iris" {
			continue
		}
		count++
		if item.Category != "barstyles" || item.Name != "Shima" {
			t.Fatalf("existing Shima entry was renamed or recategorized: %+v", item)
		}
		if item.Installed {
			t.Fatal("uninstalled optional Shima runtime must not appear installed")
		}
	}
	if count != 1 {
		t.Fatalf("Shima must be one existing barstyles/iris product, got %d", count)
	}
}
