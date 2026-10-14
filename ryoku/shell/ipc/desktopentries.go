package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type desktopEntryMetadata struct {
	ID           string `json:"id"`
	Name         string `json:"name,omitempty"`
	Icon         string `json:"icon,omitempty"`
	StartupClass string `json:"startupClass,omitempty"`
	Comment      string `json:"comment,omitempty"`
	noDisplay    bool
}

type noDisplayEntryIndex struct {
	Entries []desktopEntryMetadata `json:"entries"`
}

func runNoDisplayEntries() int {
	entries := noDisplayDesktopEntries(desktopEntryRoots())
	data, err := json.Marshal(noDisplayEntryIndex{Entries: entries})
	if err != nil {
		fmt.Fprintln(os.Stderr, "ryoku-shell: no-display-entries:", err)
		return 1
	}
	fmt.Println(string(data))
	return 0
}

func desktopEntryRoots() []string {
	home := os.Getenv("HOME")
	dataHome := os.Getenv("XDG_DATA_HOME")
	if dataHome == "" {
		dataHome = filepath.Join(home, ".local", "share")
	}
	dataDirs := os.Getenv("XDG_DATA_DIRS")
	if dataDirs == "" {
		dataDirs = "/usr/local/share:/usr/share"
	}
	roots := []string{filepath.Join(dataHome, "applications")}
	for _, dir := range filepath.SplitList(dataDirs) {
		if dir != "" {
			roots = append(roots, filepath.Join(dir, "applications"))
		}
	}
	return roots
}

func noDisplayDesktopEntries(roots []string) []desktopEntryMetadata {
	type candidate struct {
		id   string
		path string
	}
	seen := make(map[string]struct{})
	entries := make([]desktopEntryMetadata, 0, 32)
	for _, root := range roots {
		var found []candidate
		_ = filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
			if err != nil || entry.IsDir() || !strings.HasSuffix(entry.Name(), ".desktop") {
				return nil
			}
			rel, relErr := filepath.Rel(root, path)
			if relErr == nil {
				found = append(found, candidate{
					id:   strings.ReplaceAll(filepath.ToSlash(rel), "/", "-"),
					path: path,
				})
			}
			return nil
		})
		sort.Slice(found, func(i, j int) bool { return found[i].id < found[j].id })
		for _, candidate := range found {
			if _, exists := seen[candidate.id]; exists {
				continue
			}
			seen[candidate.id] = struct{}{}
			entry, ok := readDesktopEntry(candidate.path)
			if !ok || !entry.noDisplay {
				continue
			}
			entry.ID = candidate.id
			entries = append(entries, entry)
		}
	}
	return entries
}

func readDesktopEntry(path string) (desktopEntryMetadata, bool) {
	file, err := os.Open(path)
	if err != nil {
		return desktopEntryMetadata{}, false
	}
	defer file.Close()

	var entry desktopEntryMetadata
	inDesktopEntry := false
	foundSection := false
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			inDesktopEntry = line == "[Desktop Entry]"
			foundSection = foundSection || inDesktopEntry
			continue
		}
		if !inDesktopEntry {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		switch strings.TrimSpace(key) {
		case "Name":
			entry.Name = strings.TrimSpace(value)
		case "Icon":
			entry.Icon = strings.TrimSpace(value)
		case "StartupWMClass":
			entry.StartupClass = strings.TrimSpace(value)
		case "Comment":
			entry.Comment = strings.TrimSpace(value)
		case "NoDisplay":
			entry.noDisplay = strings.EqualFold(strings.TrimSpace(value), "true")
		}
	}
	return entry, foundSection && scanner.Err() == nil
}
