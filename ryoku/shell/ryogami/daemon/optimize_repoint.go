package main

import (
	"os"
	"path/filepath"
	"strings"
)

// repointOptimizedWallpaper moves state to the replacement before the catalog
// rescan sees it. Nothing is repainted: the decoded frame stays on screen while
// future restores and captures use the new file.
func (d *daemon) repointOptimizedWallpaper(oldPath, newPath string) {
	oldPath = filepath.Clean(oldPath)
	newPath = filepath.Clean(newPath)
	if oldPath == "." || newPath == "." || oldPath == newPath {
		return
	}
	matches := func(path string) bool {
		return path != "" && filepath.Clean(path) == oldPath
	}

	cacheDir := d.config().cacheDir()
	outputs := map[string]map[string]interface{}{}
	loadJSON(filepath.Join(cacheDir, "outputs.json"), &outputs)
	outputsChanged := false
	for _, entry := range outputs {
		path, _ := entry["path"].(string)
		if matches(path) {
			entry["path"] = newPath
			outputsChanged = true
		}
	}
	if outputsChanged {
		saveJSON(filepath.Join(cacheDir, "outputs.json"), outputs)
		syncWallState(outputs)
	} else if recorded, err := os.ReadFile(wallStatePath()); err == nil && matches(strings.TrimSpace(string(recorded))) {
		syncWallState(map[string]map[string]interface{}{
			"*": {"type": "static", "path": newPath},
		})
	}

	if d.workspaces != nil {
		d.workspaces.mu.Lock()
		changed := false
		for key, wall := range d.workspaces.state.Assignments {
			if matches(wall.Path) {
				wall.Path = newPath
				d.workspaces.state.Assignments[key] = wall
				changed = true
			}
		}
		if changed {
			d.workspaces.saveLocked()
		}
		d.workspaces.mu.Unlock()
	}

	keyReplacements := map[string]string{}
	if d.store != nil {
		d.store.mu.Lock()
		changed := false
		for key, entry := range d.store.entries {
			if !matches(entry.Path) && !matches(entry.VideoFile) {
				continue
			}
			if matches(entry.Path) {
				entry.Path = newPath
				entry.Name = strings.TrimSuffix(entry.Name, filepath.Ext(entry.Name)) + filepath.Ext(newPath)
				newKey := strings.ReplaceAll(filepath.ToSlash(entry.Name), "/", "--")
				entry.Key = newKey
				if key != newKey {
					keyReplacements[key] = newKey
				}
			}
			if matches(entry.VideoFile) {
				entry.VideoFile = newPath
			}
			delete(d.store.entries, key)
			d.store.entries[entry.Key] = entry
			changed = true
		}
		if changed {
			d.store.saveLocked()
		}
		d.store.mu.Unlock()
	}

	if d.playlists != nil && len(keyReplacements) > 0 {
		d.playlists.mu.Lock()
		changed := false
		for i := range d.playlists.st.Lists {
			for j, key := range d.playlists.st.Lists[i].Members {
				if replacement, ok := keyReplacements[key]; ok {
					d.playlists.st.Lists[i].Members[j] = replacement
					changed = true
				}
			}
		}
		if changed {
			d.playlists.saveLocked()
		}
		d.playlists.mu.Unlock()
	}

	d.currentMu.Lock()
	if d.current == filepath.Base(oldPath) {
		d.current = filepath.Base(newPath)
	}
	d.currentMu.Unlock()

	d.paintMu.Lock()
	for output, path := range d.paintShows {
		if matches(path) {
			d.paintShows[output] = newPath
		}
	}
	d.paintMu.Unlock()
}
