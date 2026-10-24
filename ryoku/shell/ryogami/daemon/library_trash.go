package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"
)

func ryogamiDataDir() string {
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		return filepath.Join(d, "ryogami")
	}
	return filepath.Join(home(), ".local", "share", "ryogami")
}

func ryogamiTrashDir() string   { return filepath.Join(ryogamiDataDir(), "trash") }
func trashManifestPath() string { return filepath.Join(ryogamiTrashDir(), "manifest.json") }

// The trash is skwd's recovery storage for the originals image optimisation
// replaced; the retention settings decide when they go for good.
type trashItem struct {
	Name         string `json:"name"`
	OriginalPath string `json:"original_path"`
	StoredPath   string `json:"stored_path"`
	TrashedAt    int64  `json:"trashed_at"`
}

var trashMu sync.Mutex

func init() {
	onStart(func(d *daemon) { go d.trashRetentionLoop() })
}

func loadTrashManifest() []trashItem {
	var items []trashItem
	if b, err := os.ReadFile(trashManifestPath()); err == nil {
		_ = json.Unmarshal(resolvedJSON(b), &items)
	}
	return items
}

func saveTrashManifest(items []trashItem) error {
	if err := os.MkdirAll(ryogamiTrashDir(), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(items, "", "  ")
	if err != nil {
		return err
	}
	tmp := trashManifestPath() + ".tmp"
	if err := os.WriteFile(tmp, portableJSON(b), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, trashManifestPath())
}

// trashOriginal moves an original its optimised replacement just superseded into the trash.
func trashOriginal(src string) error {
	if src == "" || !fileExists(src) {
		return nil
	}
	if err := os.MkdirAll(ryogamiTrashDir(), 0o755); err != nil {
		return err
	}
	name := filepath.Base(src)
	stored := filepath.Join(ryogamiTrashDir(), fmt.Sprintf("%d-%s", time.Now().UnixNano(), name))
	if err := trashMoveFile(src, stored); err != nil {
		return err
	}
	trashMu.Lock()
	defer trashMu.Unlock()
	return saveTrashManifest(append(loadTrashManifest(), trashItem{
		Name: name, OriginalPath: src, StoredPath: stored, TrashedAt: time.Now().Unix(),
	}))
}

func (d *daemon) trashRetentionLoop() {
	for {
		d.cleanTrash()
		time.Sleep(24 * time.Hour)
	}
}

func (d *daemon) cleanTrash() {
	if !d.settingBool("performance.autoDeleteImageTrash") {
		return
	}
	days := int(d.settingNumber("performance.imageTrashDays"))
	trashMu.Lock()
	defer trashMu.Unlock()
	items := loadTrashManifest()
	if len(items) == 0 {
		return
	}
	cutoff := time.Now().AddDate(0, 0, -days).Unix()
	kept := items[:0]
	for _, it := range items {
		if days <= 0 || it.TrashedAt <= cutoff {
			_ = os.Remove(it.StoredPath)
			continue
		}
		kept = append(kept, it)
	}
	if len(kept) != len(items) {
		_ = saveTrashManifest(kept)
	}
}

// The trash may sit on another filesystem, so a failed rename falls back to copy and remove.
func trashMoveFile(src, dst string) error {
	if err := os.Rename(src, dst); err == nil {
		return nil
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	out, err := os.Create(dst)
	if err != nil {
		in.Close()
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		in.Close()
		out.Close()
		os.Remove(dst)
		return err
	}
	in.Close()
	if err := out.Close(); err != nil {
		return err
	}
	return os.Remove(src)
}
