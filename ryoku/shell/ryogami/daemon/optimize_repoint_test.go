package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRepointOptimizedWallpaperReferences(t *testing.T) {
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	state := filepath.Join(root, "state")
	t.Setenv("XDG_STATE_HOME", state)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("HOME", root)
	if err := os.MkdirAll(cache, 0o755); err != nil {
		t.Fatal(err)
	}

	oldPath := filepath.Join(root, "walls", "scene.png")
	newPath := filepath.Join(root, "walls", "scene.webp")
	otherPath := filepath.Join(root, "walls", "other.png")
	outputs := map[string]map[string]interface{}{
		"*":    {"type": "static", "path": oldPath},
		"DP-1": {"type": "static", "path": oldPath},
		"DP-2": {"type": "static", "path": otherPath},
	}
	saveJSON(filepath.Join(cache, "outputs.json"), outputs)

	d := &daemon{paintShows: map[string]string{"": oldPath, "DP-2": otherPath}}
	d.cfg.Paths.Cache = cache
	d.current = filepath.Base(oldPath)
	d.store = openStore(cache)
	d.store.replaceAll(map[string]Entry{
		"scene.png": {Key: "scene.png", Name: "scene.png", Type: "static", Path: oldPath, Favourite: 1, ApplyCount: 7},
		"other.png": {Key: "other.png", Name: "other.png", Type: "static", Path: otherPath},
	})
	d.workspaces = newWorkspaceManager(d)
	d.workspaces.state.Assignments["wm:1"] = workspaceWall{Provider: "wm", ID: "1", Type: "static", Path: oldPath}
	d.workspaces.saveLocked()
	d.playlists = newPlaylistManager(cache, d)
	d.playlists.st.Lists = []Playlist{{ID: 1, Name: "Saved", Kind: "curated", Members: []string{"scene.png", "other.png"}}}
	d.playlists.saveLocked()

	d.repointOptimizedWallpaper(oldPath, newPath)

	persistedOutputs := map[string]map[string]interface{}{}
	loadJSON(filepath.Join(cache, "outputs.json"), &persistedOutputs)
	if got := persistedOutputs["*"]["path"]; got != newPath {
		t.Fatalf("broadcast output path = %v, want %s", got, newPath)
	}
	if got := persistedOutputs["DP-1"]["path"]; got != newPath {
		t.Fatalf("named output path = %v, want %s", got, newPath)
	}
	if got := persistedOutputs["DP-2"]["path"]; got != otherPath {
		t.Fatalf("unrelated output path changed to %v", got)
	}
	wallState, err := os.ReadFile(filepath.Join(state, "ryoku-wallpaper"))
	if err != nil {
		t.Fatal(err)
	}
	if got := string(wallState); got != newPath+"\n" {
		t.Fatalf("wall state = %q, want %q", got, newPath+"\n")
	}

	workspaceState := workspaceWallState{}
	loadJSON(filepath.Join(cache, "workspaces.json"), &workspaceState)
	if got := workspaceState.Assignments["wm:1"].Path; got != newPath {
		t.Fatalf("workspace path = %q, want %q", got, newPath)
	}
	entry, ok := d.store.get("scene.webp")
	if !ok {
		t.Fatal("re-keyed library entry is missing")
	}
	if entry.Path != newPath || entry.Favourite != 1 || entry.ApplyCount != 7 {
		t.Fatalf("re-keyed entry = %+v", entry)
	}
	if _, ok := d.store.get("scene.png"); ok {
		t.Fatal("old library key remains")
	}

	savedPlaylists := playlistState{}
	loadJSON(filepath.Join(cache, "wallpaper", "playlists.json"), &savedPlaylists)
	if got := savedPlaylists.Lists[0].Members[0]; got != "scene.webp" {
		t.Fatalf("playlist member = %q, want scene.webp", got)
	}
	if got := d.currentName(); got != "scene.webp" {
		t.Fatalf("current name = %q, want scene.webp", got)
	}
	if got := d.showing(""); got != newPath {
		t.Fatalf("paint record = %q, want %q", got, newPath)
	}
}
