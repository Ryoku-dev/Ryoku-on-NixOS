package main

import (
	"os"
	"path/filepath"
	"testing"
)

// The wallpaper dir follows a localized Pictures folder, keeps working for
// users whose library still sits in the English default beside an empty
// localized one, and always loses to an explicitly configured path.
func TestWallpaperDirXdgResolution(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	// No XDG variable: the English default.
	t.Setenv("XDG_PICTURES_DIR", "")
	if got, want := (config{}).wallpaperDir(), filepath.Join(home, "Pictures", "Wallpapers"); got != want {
		t.Fatalf("unset XDG: got %q, want %q", got, want)
	}

	// Localized folder that holds the library wins.
	localized := filepath.Join(home, "Imagens")
	if err := os.MkdirAll(filepath.Join(localized, "Wallpapers"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_PICTURES_DIR", localized)
	if got, want := (config{}).wallpaperDir(), filepath.Join(localized, "Wallpapers"); got != want {
		t.Fatalf("localized: got %q, want %q", got, want)
	}

	// Localized folder exists but is empty while the English one has the
	// files (xdg-user-dirs generated it after the fact): the library wins.
	english := filepath.Join(home, "Pictures")
	if err := os.MkdirAll(filepath.Join(english, "Wallpapers"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(filepath.Join(localized, "Wallpapers")); err != nil {
		t.Fatal(err)
	}
	if got, want := (config{}).wallpaperDir(), filepath.Join(english, "Wallpapers"); got != want {
		t.Fatalf("empty localized, english library: got %q, want %q", got, want)
	}

	// Neither exists: the localized path is the answer so a fresh library
	// grows in the right folder.
	if err := os.RemoveAll(english); err != nil {
		t.Fatal(err)
	}
	if got, want := (config{}).wallpaperDir(), filepath.Join(localized, "Wallpapers"); got != want {
		t.Fatalf("neither exists: got %q, want %q", got, want)
	}

	// An explicit configured path beats all of it.
	c := config{}
	c.Paths.Wallpaper = filepath.Join(home, "custom")
	if got, want := c.wallpaperDir(), filepath.Join(home, "custom"); got != want {
		t.Fatalf("explicit: got %q, want %q", got, want)
	}
}

func TestJSONStateStoresHomePathsPortably(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	path := filepath.Join(t.TempDir(), "state.json")
	source := filepath.Join(home, "Pictures", "Wallpapers", "scene.png")
	saveJSON(path, map[string]string{"path": source, "label": "~"})

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := string(raw), `{"label":"~","path":"~/Pictures/Wallpapers/scene.png"}`; got != want {
		t.Fatalf("stored state = %s, want %s", got, want)
	}

	var restored map[string]string
	loadJSON(path, &restored)
	if restored["path"] != source {
		t.Fatalf("restored path = %q, want %q", restored["path"], source)
	}
	if restored["label"] != "~" {
		t.Fatalf("non-path tilde changed to %q", restored["label"])
	}
}

func TestPortableCatalogListsAfterHomeMove(t *testing.T) {
	root := t.TempDir()
	oldHome := filepath.Join(root, "old-user")
	newHome := filepath.Join(root, "new-user")
	cache := filepath.Join(oldHome, ".cache", "ryogami")
	index := filepath.Join(cache, "wallpaper", "index.json")
	source := filepath.Join(oldHome, "Pictures", "Wallpapers", "scene.png")
	if err := os.MkdirAll(filepath.Dir(index), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", oldHome)
	saveJSON(index, map[string]Entry{
		"scene.png": {Key: "scene.png", Name: "scene.png", Type: "static", Path: source},
	})
	if err := os.Rename(oldHome, newHome); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", newHome)

	store := openStore(filepath.Join(newHome, ".cache", "ryogami"))
	rows := store.list(false)
	if len(rows) != 1 {
		t.Fatalf("catalog rows = %d, want 1", len(rows))
	}
	if got, want := rows[0].Path, filepath.Join(newHome, "Pictures", "Wallpapers", "scene.png"); got != want {
		t.Fatalf("catalog path = %q, want %q", got, want)
	}
}

func TestResolveShellQMLUsesRuntimeDataHome(t *testing.T) {
	data := t.TempDir()
	t.Setenv("RYOGAMI_SHELL_QML", "")
	t.Setenv("XDG_DATA_HOME", data)
	entry := filepath.Join(data, "ryogami", "shell.qml")
	if err := os.MkdirAll(filepath.Dir(entry), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(entry, []byte("import QtQuick\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := resolveShellQML(); got != entry {
		t.Fatalf("picker entry = %q, want %q", got, entry)
	}
}
