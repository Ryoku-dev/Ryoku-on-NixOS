package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"sync"
)

// Entry is one catalog row, serialized verbatim into wall.list responses. The
// field names are the wire contract the picker parses; they mirror the
// Rust daemon's sqlite row exactly, though the Go store persists them as one
// JSON index instead of a database.
type Entry struct {
	Key        string `json:"key"`
	Name       string `json:"name"`
	Type       string `json:"type"`
	Path       string `json:"path"`
	Thumb      string `json:"thumb"`
	ThumbSm    string `json:"thumb_sm"`
	Favourite  int    `json:"favourite"`
	Hue        int    `json:"hue"`
	Sat        int    `json:"sat"`
	Richness   int    `json:"richness"`
	VideoFile  string `json:"video_file"`
	VideoPrev  string `json:"video_prev"`
	WeID       string `json:"we_id"`
	WeType     string `json:"we_type,omitempty"`
	Tags       string `json:"tags,omitempty"`
	Preview    string `json:"preview,omitempty"`
	Filesize   int64  `json:"filesize"`
	Width      int    `json:"width"`
	Height     int    `json:"height"`
	Mtime      int64  `json:"mtime"`
	ApplyCount int    `json:"apply_count"`
}

// store holds the wallpaper catalog and the small state kv the picker persists
// through state.get/state.set. Both live under the cache dir and are written
// atomically; favourites and counts survive rescans via the merge in ScanDirs.
type store struct {
	mu      sync.Mutex
	entries map[string]Entry
	state   map[string]string
	dir     string // cacheDir/wallpaper
}

func openStore(cacheDir string) *store {
	s := &store{
		entries: map[string]Entry{},
		state:   map[string]string{},
		dir:     filepath.Join(cacheDir, "wallpaper"),
	}
	_ = os.MkdirAll(s.dir, 0o755)
	loadJSON(filepath.Join(s.dir, "index.json"), &s.entries)
	loadJSON(filepath.Join(s.dir, "state.json"), &s.state)
	return s
}

func portableJSON(b []byte) []byte {
	h := filepath.Clean(home())
	if h == "." || h == string(filepath.Separator) {
		return b
	}
	prefix, _ := json.Marshal(h + string(filepath.Separator))
	return bytes.ReplaceAll(b, prefix[:len(prefix)-1], []byte(`"~/`))
}

func resolvedJSON(b []byte) []byte {
	h := filepath.Clean(home())
	if h == "." || h == string(filepath.Separator) {
		return b
	}
	prefix, _ := json.Marshal(h + string(filepath.Separator))
	return bytes.ReplaceAll(b, []byte(`"~/`), prefix[:len(prefix)-1])
}

func loadJSON(path string, into interface{}) {
	b, err := os.ReadFile(path)
	if err != nil {
		return
	}
	_ = json.Unmarshal(resolvedJSON(b), into)
}

func saveJSON(path string, v interface{}) {
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, portableJSON(b), 0o644); err != nil {
		return
	}
	_ = os.Rename(tmp, path)
}

func (s *store) saveLocked() {
	saveJSON(filepath.Join(s.dir, "index.json"), s.entries)
}

func (s *store) replaceAll(entries map[string]Entry) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.entries = entries
	s.saveLocked()
}

func (s *store) snapshotEntries() map[string]Entry {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make(map[string]Entry, len(s.entries))
	for k, v := range s.entries {
		out[k] = v
	}
	return out
}

// list returns rows sorted by name, matching the Rust daemon's stable order.
func (s *store) list(favouritesOnly bool) []Entry {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Entry, 0, len(s.entries))
	for _, e := range s.entries {
		if favouritesOnly && e.Favourite == 0 {
			continue
		}
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func (s *store) get(key string) (Entry, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, okKey := s.entries[key]
	return e, okKey
}

func (s *store) mutate(key string, fn func(*Entry)) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, okKey := s.entries[key]
	if !okKey {
		return false
	}
	fn(&e)
	s.entries[key] = e
	s.saveLocked()
	return true
}

func (s *store) remove(key string) (Entry, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, okKey := s.entries[key]
	if okKey {
		delete(s.entries, key)
		s.saveLocked()
	}
	return e, okKey
}

func (s *store) stateGet(key string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	v, okKey := s.state[key]
	return v, okKey
}

func (s *store) stateSet(key string, val *string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if val == nil {
		delete(s.state, key)
	} else {
		s.state[key] = *val
	}
	saveJSON(filepath.Join(s.dir, "state.json"), s.state)
}
