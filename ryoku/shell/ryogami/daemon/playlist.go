package main

import (
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Playlist is one ordered set of wallpapers the picker manages, reimplementing
// skwd-wall V2's playlists (src/contracts/playlists.rs). Curated lists hold
// explicit member keys; smart lists resolve members from a saved query against
// the catalog. State persists to playlists.json in the store dir.
type Playlist struct {
	ID       int64    `json:"id"`
	Name     string   `json:"name"`
	Kind     string   `json:"kind"`   // "curated" | "smart"
	Source   string   `json:"source"` // smart query; empty for curated
	Order    string   `json:"order"`  // "added" | "name" | "shuffle"
	Dwell    int64    `json:"dwell"`  // seconds between rotations
	Position int64    `json:"position"`
	Members  []string `json:"members"` // wallpaper keys (curated only)
}

// playlistAssignment binds one output (monitor) to the playlist rotating on it.
type playlistAssignment struct {
	Output string `json:"output"`
	ID     int64  `json:"id"`
}

type playlistState struct {
	Lists       []Playlist           `json:"playlists"`
	Assignments []playlistAssignment `json:"assignments"`
	NextID      int64                `json:"nextID"`
}

// playlistManager owns playlist CRUD, per-output assignment, persistence, and
// the rotation timers. It mirrors randomRotation's ticker model, one ticker
// per active playlist, advancing position and applying to assigned outputs.
type playlistManager struct {
	mu    sync.Mutex
	dir   string
	st    playlistState
	stops map[int64]chan struct{}
	d     *daemon
}

func newPlaylistManager(cacheDir string, d *daemon) *playlistManager {
	m := &playlistManager{
		dir:   filepath.Join(cacheDir, "wallpaper"),
		stops: map[int64]chan struct{}{},
		d:     d,
	}
	loadJSON(filepath.Join(m.dir, "playlists.json"), &m.st)
	if m.st.NextID < 1 {
		m.st.NextID = 1
	}
	return m
}

func (m *playlistManager) saveLocked() {
	saveJSON(filepath.Join(m.dir, "playlists.json"), &m.st)
}

func (m *playlistManager) findLocked(id int64) *Playlist {
	for i := range m.st.Lists {
		if m.st.Lists[i].ID == id {
			return &m.st.Lists[i]
		}
	}
	return nil
}

// snapshot returns the playlists + assignments + outputs the picker renders.
func (m *playlistManager) snapshot() map[string]interface{} {
	m.mu.Lock()
	defer m.mu.Unlock()
	lists := make([]map[string]interface{}, 0, len(m.st.Lists))
	for i := range m.st.Lists {
		pl := &m.st.Lists[i]
		lists = append(lists, map[string]interface{}{
			"id":       pl.ID,
			"name":     pl.Name,
			"kind":     kindOr(pl.Kind),
			"source":   nullable(pl.Source),
			"order":    orderOr(pl.Order),
			"dwell":    dwellOr(pl.Dwell),
			"position": pl.Position,
			"count":    len(m.resolveLocked(pl)),
		})
	}
	assigns := make([]map[string]interface{}, 0, len(m.st.Assignments))
	for _, a := range m.st.Assignments {
		assigns = append(assigns, map[string]interface{}{"output": a.Output, "id": a.ID})
	}
	return map[string]interface{}{
		"playlists":   lists,
		"assignments": assigns,
		"outputs":     m.d.outputNames(),
	}
}

func (m *playlistManager) create(name string) int64 {
	m.mu.Lock()
	defer m.mu.Unlock()
	id := m.st.NextID
	m.st.NextID++
	m.st.Lists = append(m.st.Lists, Playlist{
		ID: id, Name: name, Kind: "curated", Order: "added", Dwell: 300,
	})
	m.saveLocked()
	return id
}

func (m *playlistManager) update(id int64, field, value string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	pl := m.findLocked(id)
	if pl == nil {
		return false
	}
	switch field {
	case "name":
		pl.Name = value
	case "dwell":
		pl.Dwell = parseDwell(value)
	case "source":
		pl.Source = value
	case "order":
		pl.Order = value
	case "kind":
		pl.Kind = value
	default:
		return false
	}
	m.saveLocked()
	restart := m.isActiveLocked(id)
	if restart {
		m.startRotationLocked(id)
	}
	return true
}

func (m *playlistManager) delete(id int64) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := m.st.Lists[:0]
	found := false
	for _, pl := range m.st.Lists {
		if pl.ID == id {
			found = true
			continue
		}
		out = append(out, pl)
	}
	m.st.Lists = out
	m.dropAssignmentsLocked(id)
	m.stopRotationLocked(id)
	m.saveLocked()
	return found
}

func (m *playlistManager) addMember(id int64, key string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	pl := m.findLocked(id)
	if pl == nil {
		return false
	}
	for _, k := range pl.Members {
		if k == key {
			return true
		}
	}
	pl.Members = append(pl.Members, key)
	m.saveLocked()
	return true
}

func (m *playlistManager) removeMember(id int64, key string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	pl := m.findLocked(id)
	if pl == nil {
		return false
	}
	out := pl.Members[:0]
	for _, k := range pl.Members {
		if k != key {
			out = append(out, k)
		}
	}
	pl.Members = out
	m.saveLocked()
	return true
}

// moveMember shifts key by delta positions within a curated list.
func (m *playlistManager) moveMember(id int64, key string, delta int64) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	pl := m.findLocked(id)
	if pl == nil {
		return false
	}
	idx := -1
	for i, k := range pl.Members {
		if k == key {
			idx = i
			break
		}
	}
	if idx < 0 {
		return false
	}
	dst := idx + int(delta)
	if dst < 0 {
		dst = 0
	}
	if dst >= len(pl.Members) {
		dst = len(pl.Members) - 1
	}
	k := pl.Members[idx]
	pl.Members = append(pl.Members[:idx], pl.Members[idx+1:]...)
	tail := append([]string{k}, pl.Members[dst:]...)
	pl.Members = append(pl.Members[:dst], tail...)
	m.saveLocked()
	return true
}

// members resolves the ordered member rows for the picker's detail panel.
func (m *playlistManager) members(id int64) []map[string]interface{} {
	m.mu.Lock()
	defer m.mu.Unlock()
	pl := m.findLocked(id)
	if pl == nil {
		return nil
	}
	keys := m.resolveLocked(pl)
	rows := make([]map[string]interface{}, 0, len(keys))
	for _, k := range keys {
		e, ok := m.d.store.get(k)
		if !ok {
			rows = append(rows, map[string]interface{}{"key": k})
			continue
		}
		rows = append(rows, map[string]interface{}{
			"key":      e.Key,
			"kind":     e.Type,
			"preview":  nullable(e.VideoPrev),
			"thumb":    nullable(e.Thumb),
			"thumb_sm": nullable(e.ThumbSm),
		})
	}
	return rows
}

// assign binds output to playlist id (replacing any prior binding) and starts
// rotation, applying the current member immediately.
func (m *playlistManager) assign(output string, id int64) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.findLocked(id) == nil {
		return false
	}
	m.setAssignmentLocked(output, id)
	m.saveLocked()
	m.startRotationLocked(id)
	m.applyCurrentLocked(id, []string{output})
	return true
}

// toggle flips output's binding to id: on if absent/different, off if same.
func (m *playlistManager) toggle(output string, id int64) bool {
	m.mu.Lock()
	cur, has := m.assignedLocked(output)
	m.mu.Unlock()
	if has && cur == id {
		return m.unassign(output)
	}
	return m.assign(output, id)
}

func (m *playlistManager) unassign(output string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	id, has := m.assignedLocked(output)
	if !has {
		return false
	}
	m.removeAssignmentLocked(output)
	m.saveLocked()
	if !m.hasOutputsLocked(id) {
		m.stopRotationLocked(id)
	}
	return true
}

// stop unassigns every output from id and halts its rotation.
func (m *playlistManager) stop(id int64) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.dropAssignmentsLocked(id)
	m.stopRotationLocked(id)
	m.saveLocked()
	return true
}

// stopAll halts every assigned playlist's rotation and drops its bindings, so
// nothing auto-advances and resumeAll finds nothing to restart. Used by the
// unified "auto-rotate off" control.
func (m *playlistManager) stopAll() {
	m.mu.Lock()
	seen := map[int64]bool{}
	ids := []int64{}
	for _, a := range m.st.Assignments {
		if !seen[a.ID] {
			seen[a.ID] = true
			ids = append(ids, a.ID)
		}
	}
	m.mu.Unlock()
	for _, id := range ids {
		m.stop(id)
	}
}

// anyAssigned reports whether any playlist is bound to an output (i.e. rotating).
func (m *playlistManager) anyAssigned() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.st.Assignments) > 0
}

// playNow applies the current member of id to its outputs right away.
func (m *playlistManager) playNow(id int64) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.findLocked(id) == nil {
		return false
	}
	m.applyCurrentLocked(id, m.outputsForLocked(id))
	return true
}

// resumeAll restarts rotation timers for every assigned playlist on startup.
func (m *playlistManager) resumeAll() {
	m.mu.Lock()
	defer m.mu.Unlock()
	seen := map[int64]bool{}
	for _, a := range m.st.Assignments {
		if !seen[a.ID] {
			seen[a.ID] = true
			m.startRotationLocked(a.ID)
		}
	}
}

// ---- rotation ----

func (m *playlistManager) startRotationLocked(id int64) {
	m.stopRotationLocked(id)
	pl := m.findLocked(id)
	if pl == nil {
		return
	}
	dwell := dwellOr(pl.Dwell)
	stop := make(chan struct{})
	m.stops[id] = stop
	go func() {
		t := time.NewTicker(time.Duration(dwell) * time.Second)
		defer t.Stop()
		for {
			select {
			case <-t.C:
				m.advance(id)
			case <-stop:
				return
			}
		}
	}()
}

func (m *playlistManager) stopRotationLocked(id int64) {
	if ch, ok := m.stops[id]; ok {
		close(ch)
		delete(m.stops, id)
	}
}

// advance steps id to its next member and applies it to id's outputs.
func (m *playlistManager) advance(id int64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	pl := m.findLocked(id)
	if pl == nil {
		return
	}
	keys := m.resolveLocked(pl)
	if len(keys) == 0 {
		return
	}
	pl.Position = (pl.Position + 1) % int64(len(keys))
	m.saveLocked()
	m.applyKeyLocked(keys[pl.Position], m.outputsForLocked(id))
}

func (m *playlistManager) applyCurrentLocked(id int64, outputs []string) {
	pl := m.findLocked(id)
	if pl == nil {
		return
	}
	keys := m.resolveLocked(pl)
	if len(keys) == 0 {
		return
	}
	if pl.Position < 0 || pl.Position >= int64(len(keys)) {
		pl.Position = 0
	}
	m.applyKeyLocked(keys[pl.Position], outputs)
}

// outputNames lists the connected outputs (monitors) from the persisted map
// wall.outputs serves, sorted for a stable picker order.
func (d *daemon) outputNames() []string {
	state := map[string]map[string]interface{}{}
	loadJSON(filepath.Join(d.config().cacheDir(), "outputs.json"), &state)
	names := make([]string, 0, len(state))
	for k := range state {
		names = append(names, k)
	}
	sort.Strings(names)
	return names
}

func (m *playlistManager) applyKeyLocked(key string, outputs []string) {
	e, ok := m.d.store.get(key)
	if !ok {
		return
	}
	path := e.VideoFile
	if path == "" {
		path = filepath.Join(m.d.config().wallpaperDir(), e.Name)
	}
	_ = m.d.applyWallpaperReason("playlist", typeOf(path), path, "set", outputs, nil, nil)
}

// resolveLocked returns the ordered member keys for a list: explicit members
// for curated, or a name-substring query over the catalog for smart lists.
func (m *playlistManager) resolveLocked(pl *Playlist) []string {
	var keys []string
	if pl.Kind == "smart" {
		q := strings.ToLower(strings.TrimSpace(pl.Source))
		for _, e := range m.d.store.list(false) {
			if q == "" || strings.Contains(strings.ToLower(e.Name), q) {
				keys = append(keys, e.Key)
			}
		}
	} else {
		keys = append(keys, pl.Members...)
	}
	if pl.Order == "name" {
		sort.Strings(keys)
	}
	return keys
}

// ---- assignment helpers ----

func (m *playlistManager) assignedLocked(output string) (int64, bool) {
	for _, a := range m.st.Assignments {
		if a.Output == output {
			return a.ID, true
		}
	}
	return 0, false
}

func (m *playlistManager) isActiveLocked(id int64) bool { return m.hasOutputsLocked(id) }

func (m *playlistManager) hasOutputsLocked(id int64) bool {
	for _, a := range m.st.Assignments {
		if a.ID == id {
			return true
		}
	}
	return false
}

func (m *playlistManager) outputsForLocked(id int64) []string {
	var out []string
	for _, a := range m.st.Assignments {
		if a.ID == id {
			out = append(out, a.Output)
		}
	}
	return out
}

func (m *playlistManager) setAssignmentLocked(output string, id int64) {
	m.removeAssignmentLocked(output)
	m.st.Assignments = append(m.st.Assignments, playlistAssignment{Output: output, ID: id})
}

func (m *playlistManager) removeAssignmentLocked(output string) {
	out := m.st.Assignments[:0]
	for _, a := range m.st.Assignments {
		if a.Output != output {
			out = append(out, a)
		}
	}
	m.st.Assignments = out
}

func (m *playlistManager) dropAssignmentsLocked(id int64) {
	out := m.st.Assignments[:0]
	for _, a := range m.st.Assignments {
		if a.ID != id {
			out = append(out, a)
		}
	}
	m.st.Assignments = out
}

// ---- small defaults ----

func kindOr(k string) string {
	if k == "" {
		return "curated"
	}
	return k
}

func orderOr(o string) string {
	if o == "" {
		return "added"
	}
	return o
}

func dwellOr(d int64) int64 {
	if d < 5 {
		return 300
	}
	return d
}

func parseDwell(s string) int64 {
	n := int64(0)
	for _, r := range strings.TrimSpace(s) {
		if r < '0' || r > '9' {
			return dwellOr(0)
		}
		n = n*10 + int64(r-'0')
	}
	return dwellOr(n)
}
