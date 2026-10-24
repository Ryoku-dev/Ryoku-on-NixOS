package main

import (
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
)

// Matches the renderer's cap on stored overrides.
const maxWeProperties = 512

// Groups and unsupported kinds are shown but not edited.
const (
	weKindBool        = "bool"
	weKindColor       = "color"
	weKindSlider      = "slider"
	weKindCombo       = "combo"
	weKindGroup       = "group"
	weKindUnsupported = "unsupported"
)

type weOption struct {
	Label string  `json:"label"`
	Value float64 `json:"value"`
}

type weProperty struct {
	Name       string      `json:"name"`
	Label      string      `json:"label"`
	Kind       string      `json:"kind"`
	Declared   string      `json:"declared"`
	Value      interface{} `json:"value"`
	Default    interface{} `json:"default"`
	Overridden bool        `json:"overridden"`
	Min        *float64    `json:"min,omitempty"`
	Max        *float64    `json:"max,omitempty"`
	Step       *float64    `json:"step,omitempty"`
	Options    []weOption  `json:"options,omitempty"`
	Condition  string      `json:"condition,omitempty"`
	Order      int64       `json:"order"`
}

func mergeProperties(declared, overrides map[string]interface{}) []weProperty {
	rows := make([]weProperty, 0, len(declared))
	for name, raw := range declared {
		entry, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		rows = append(rows, propertyRow(name, entry, overrides))
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Order != rows[j].Order {
			return rows[i].Order < rows[j].Order
		}
		return rows[i].Name < rows[j].Name
	})
	return rows
}

func propertyRow(name string, entry, overrides map[string]interface{}) weProperty {
	declared, _ := entry["type"].(string)
	def := entry["value"]
	override, has := overrides[name]
	value := def
	if has {
		value = override
	}
	label := name
	if text, ok := entry["text"].(string); ok && strings.TrimSpace(text) != "" {
		label = strings.TrimSpace(text)
	}
	order := int64(math.MaxInt64)
	if o, ok := numberOf(entry["order"]); ok {
		order = int64(o)
	}
	return weProperty{
		Name:       name,
		Label:      label,
		Kind:       resolveKind(declared, entry, def),
		Declared:   declared,
		Value:      value,
		Default:    def,
		Overridden: has,
		Min:        numberPtr(entry["min"]),
		Max:        numberPtr(entry["max"]),
		Step:       numberPtr(entry["step"]),
		Options:    optionsOf(entry["options"]),
		Condition:  stringOr(entry["condition"]),
		Order:      order,
	}
}

func resolveKind(declared string, entry map[string]interface{}, def interface{}) string {
	switch strings.ToLower(declared) {
	case "bool":
		return weKindBool
	case "color":
		return weKindColor
	case "slider":
		return weKindSlider
	case "combo":
		return weKindCombo
	case "group":
		return weKindGroup
	case "":
		return inferKind(entry, def)
	default:
		return weKindUnsupported
	}
}

func inferKind(entry map[string]interface{}, def interface{}) string {
	if _, ok := entry["options"]; ok {
		return weKindCombo
	}
	_, hasMin := entry["min"]
	_, hasMax := entry["max"]
	if hasMin && hasMax {
		return weKindSlider
	}
	switch v := def.(type) {
	case bool:
		return weKindBool
	case float64:
		return weKindSlider
	case string:
		if len(strings.Fields(v)) == 3 {
			return weKindColor
		}
	}
	return weKindUnsupported
}

func numberOf(v interface{}) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case string:
		if f, err := strconv.ParseFloat(strings.TrimSpace(n), 64); err == nil {
			return f, true
		}
	}
	return 0, false
}

func numberPtr(v interface{}) *float64 {
	if f, ok := numberOf(v); ok {
		return &f
	}
	return nil
}

func stringOr(v interface{}) string {
	s, _ := v.(string)
	return s
}

func optionsOf(v interface{}) []weOption {
	arr, ok := v.([]interface{})
	if !ok {
		return nil
	}
	out := make([]weOption, 0, len(arr))
	for _, item := range arr {
		obj, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		val, _ := numberOf(obj["value"])
		out = append(out, weOption{
			Label: strings.TrimSpace(stringOr(obj["label"])),
			Value: val,
		})
	}
	return out
}

type weSceneProps struct {
	Props map[string]interface{} `json:"props,omitempty"`
	Fps   int                    `json:"fps,omitempty"`
}

type wePropStore struct {
	d  *daemon
	mu sync.Mutex
}

func newWePropStore(d *daemon) *wePropStore {
	return &wePropStore{d: d}
}

func (s *wePropStore) path() string {
	return filepath.Join(s.d.config().cacheDir(), "wallpaper", "we_properties.json")
}

func (s *wePropStore) load() map[string]weSceneProps {
	m := map[string]weSceneProps{}
	loadJSON(s.path(), &m)
	return m
}

func (s *wePropStore) saveLocked(m map[string]weSceneProps) {
	_ = os.MkdirAll(filepath.Dir(s.path()), 0o755)
	saveJSON(s.path(), m)
}

func (s *wePropStore) overrides(weID string) map[string]interface{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.load()[weID].Props
}

func (s *wePropStore) fpsOverride(weID string) (int, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sp, ok := s.load()[weID]
	if !ok || sp.Fps <= 0 {
		return 0, false
	}
	return sp.Fps, true
}

func (s *wePropStore) setValue(weID, name string, value interface{}) {
	s.mu.Lock()
	defer s.mu.Unlock()
	m := s.load()
	sp := m[weID]
	if sp.Props == nil {
		sp.Props = map[string]interface{}{}
	}
	if _, exists := sp.Props[name]; !exists && len(sp.Props) >= maxWeProperties {
		return
	}
	sp.Props[name] = value
	m[weID] = sp
	s.saveLocked(m)
}

func (s *wePropStore) resetValue(weID, name string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	m := s.load()
	sp, ok := m[weID]
	if !ok {
		return
	}
	delete(sp.Props, name)
	m[weID] = sp
	s.saveLocked(m)
}

// resetAll drops every property override and the frame-rate override for one scene.
func (s *wePropStore) resetAll(weID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	m := s.load()
	if _, ok := m[weID]; !ok {
		return
	}
	delete(m, weID)
	s.saveLocked(m)
}

func (s *wePropStore) setFps(weID string, fps int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	m := s.load()
	sp := m[weID]
	sp.Fps = fps
	m[weID] = sp
	s.saveLocked(m)
}

func clampFps(f int) int {
	if f < 1 {
		return 1
	}
	if f > 240 {
		return 240
	}
	return f
}

func (w *workshopLib) globalFps() int {
	return clampFps(wkInt(w.d.setting("weRender.fps"), 30))
}

func (w *workshopLib) sceneFps(weID string) int {
	if fps, ok := w.props.fpsOverride(weID); ok {
		return clampFps(fps)
	}
	return w.globalFps()
}

// properties returns the scene's rows, its own frame rate (nil while it follows
// the global rate) and the global rate.
func (w *workshopLib) properties(weID string) ([]weProperty, interface{}, int) {
	if !validWeID(weID) {
		return nil, nil, w.globalFps()
	}
	itemDir := filepath.Join(w.workshopDir(), weID)
	declared := map[string]interface{}{}
	if project, err := resolveProject(itemDir); err == nil {
		declared = project.declarations()
	}
	rows := mergeProperties(declared, w.props.overrides(weID))
	var fps interface{}
	if f, ok := w.props.fpsOverride(weID); ok {
		fps = clampFps(f)
	}
	return rows, fps, w.globalFps()
}

func (w *workshopLib) reapplyIfCurrent(weID string) bool {
	d := w.d
	itemDir := filepath.Join(w.workshopDir(), weID)
	state := map[string]map[string]interface{}{}
	loadJSON(filepath.Join(d.config().cacheDir(), "outputs.json"), &state)
	mute := map[string]bool{}
	volume := map[string]int{}
	var outs []string
	broadcast := false
	def := wallAudioDefaults()
	for out, e := range state {
		if e["type"] != "we" {
			continue
		}
		if p, _ := e["path"].(string); p != itemDir {
			continue
		}
		m, vol := entryAudio(e, def)
		mute[out] = m
		volume[out] = vol
		if out == "*" {
			broadcast = true
			continue
		}
		outs = append(outs, out)
	}
	// The low-level drive skips the apply guards, persistence and post-processing a fresh pick runs.
	if broadcast {
		return d.driveWE(weID, itemDir, nil, mute, volume) == nil
	}
	if len(outs) == 0 {
		return false
	}
	return d.driveWE(weID, itemDir, outs, mute, volume) == nil
}
