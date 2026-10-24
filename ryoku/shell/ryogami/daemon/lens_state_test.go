package main

import (
	"os"
	"path/filepath"
	"testing"
)

func lensEnvIsolate(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	// Keep the developer's real config and model library out of the state checks.
	t.Setenv("HOME", filepath.Join(root, "home"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
	return root
}

func writeExec(t *testing.T, path string) string {
	t.Helper()
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func writeFileAt(t *testing.T, path string) string {
	t.Helper()
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestSemanticStateReportsWhatIsMissing pins the honest condition Describe search shows, so a
// fresh box says "import a model" instead of silently returning nothing.
func TestSemanticStateReportsWhatIsMissing(t *testing.T) {
	root := lensEnvIsolate(t)
	helper := writeExec(t, filepath.Join(root, "skwd-lens"))
	runtime := writeFileAt(t, filepath.Join(root, "libonnxruntime.so"))
	manifest := writeFileAt(t, filepath.Join(root, "semantic-pack.json"))

	newMgr := func() *lensManager { return newLensManager(&daemon{store: openStore(t.TempDir())}) }

	t.Run("no helper is unavailable", func(t *testing.T) {
		t.Setenv("SKWD_LENS_BIN", filepath.Join(root, "absent", "skwd-lens"))
		if got := newMgr().semanticState(); got != "unavailable" {
			t.Fatalf("no helper: want unavailable, got %q", got)
		}
	})

	t.Run("no model asks for a pack", func(t *testing.T) {
		t.Setenv("SKWD_LENS_BIN", helper)
		t.Setenv("SKWD_LENS_MANIFEST", filepath.Join(root, "absent", "semantic-pack.json"))
		if got := newMgr().semanticState(); got != "noModel" {
			t.Fatalf("missing model: want noModel, got %q", got)
		}
	})

	t.Run("missing runtime is unavailable", func(t *testing.T) {
		t.Setenv("SKWD_LENS_BIN", helper)
		t.Setenv("SKWD_LENS_MANIFEST", manifest)
		t.Setenv("SKWD_LENS_ORT_DYLIB", filepath.Join(root, "absent", "libonnxruntime.so"))
		if got := newMgr().semanticState(); got != "unavailable" {
			t.Fatalf("missing runtime: want unavailable, got %q", got)
		}
	})

	t.Run("all present with an empty library is ready", func(t *testing.T) {
		t.Setenv("SKWD_LENS_BIN", helper)
		t.Setenv("SKWD_LENS_MANIFEST", manifest)
		t.Setenv("SKWD_LENS_ORT_DYLIB", runtime)
		t.Setenv("SKWD_LENS_INDEX", filepath.Join(root, "index.sidx"))
		if got := newMgr().semanticState(); got != "ready" {
			t.Fatalf("empty library: want ready, got %q", got)
		}
	})

	t.Run("wallpapers without an index are indexing", func(t *testing.T) {
		t.Setenv("SKWD_LENS_BIN", helper)
		t.Setenv("SKWD_LENS_MANIFEST", manifest)
		t.Setenv("SKWD_LENS_ORT_DYLIB", runtime)
		t.Setenv("SKWD_LENS_INDEX", filepath.Join(root, "missing.sidx"))
		m := newMgr()
		m.d.store.replaceAll(map[string]Entry{
			"a": {Key: "a", Name: "a", Type: "static", Thumb: "/t/a.webp", Mtime: 1, Width: 1920, Height: 1080},
		})
		if got := m.semanticState(); got != "indexing" {
			t.Fatalf("no index yet: want indexing, got %q", got)
		}
	})
}

// TestLensHelperAvailabilityIndependentOfModel proves the settings import controls stay reachable
// when skwd-lens is installed but no model is: the "lens" gate needs a model, "lensHelper" does not.
func TestLensHelperAvailabilityIndependentOfModel(t *testing.T) {
	root := lensEnvIsolate(t)
	t.Setenv("SKWD_LENS_BIN", writeExec(t, filepath.Join(root, "skwd-lens")))
	t.Setenv("SKWD_LENS_ORT_DYLIB", writeFileAt(t, filepath.Join(root, "libonnxruntime.so")))
	t.Setenv("SKWD_LENS_MANIFEST", filepath.Join(root, "absent", "semantic-pack.json"))

	d := &daemon{store: openStore(t.TempDir())}
	if availability["lens"](d) {
		t.Fatalf("lens should be unavailable without a model")
	}
	if !availability["lensHelper"](d) {
		t.Fatalf("lensHelper should be available when skwd-lens and its runtime are present")
	}
}
