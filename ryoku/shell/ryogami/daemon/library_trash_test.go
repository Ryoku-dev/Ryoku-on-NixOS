package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestTrashOriginalKeepsARecoverableCopy(t *testing.T) {
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	src := filepath.Join(t.TempDir(), "pic.png")
	if err := os.WriteFile(src, []byte("image-bytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := trashOriginal(src); err != nil {
		t.Fatalf("trashOriginal: %v", err)
	}
	if fileExists(src) {
		t.Fatal("original still in the library after trashing")
	}
	items := loadTrashManifest()
	if len(items) != 1 || items[0].OriginalPath != src {
		t.Fatalf("manifest = %+v, want one item for %s", items, src)
	}
	if got, err := os.ReadFile(items[0].StoredPath); err != nil || string(got) != "image-bytes" {
		t.Fatalf("stored copy = %q (err %v), want the original bytes", got, err)
	}
}

// TestCleanTrashHonoursRetention: only items past the retention window go, and
// only while auto-delete is on.
func TestCleanTrashHonoursRetention(t *testing.T) {
	d := newSettingsDaemon(t)
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	if err := os.MkdirAll(ryogamiTrashDir(), 0o755); err != nil {
		t.Fatal(err)
	}
	stored := func(name string, age time.Duration) trashItem {
		p := filepath.Join(ryogamiTrashDir(), name)
		if err := os.WriteFile(p, []byte(name), 0o644); err != nil {
			t.Fatal(err)
		}
		return trashItem{Name: name, StoredPath: p, TrashedAt: time.Now().Add(-age).Unix()}
	}
	old := stored("old.png", 10*24*time.Hour)
	fresh := stored("fresh.png", time.Hour)
	if err := saveTrashManifest([]trashItem{old, fresh}); err != nil {
		t.Fatal(err)
	}
	writeRyogami := func(body string) {
		if err := os.MkdirAll(filepath.Dir(configPath()), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(configPath(), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	writeRyogami(`{"performance": {"autoDeleteImageTrash": false, "imageTrashDays": 7}}`)
	d.cleanTrash()
	if !fileExists(old.StoredPath) {
		t.Fatal("auto-delete off must keep every trashed original")
	}

	writeRyogami(`{"performance": {"autoDeleteImageTrash": true, "imageTrashDays": 7}}`)
	d.cleanTrash()
	if fileExists(old.StoredPath) || !fileExists(fresh.StoredPath) {
		t.Fatalf("after cleanup old exists=%v fresh exists=%v, want only fresh", fileExists(old.StoredPath), fileExists(fresh.StoredPath))
	}
	if items := loadTrashManifest(); len(items) != 1 || items[0].Name != "fresh.png" {
		t.Fatalf("manifest after cleanup = %+v, want only fresh.png", items)
	}
}
