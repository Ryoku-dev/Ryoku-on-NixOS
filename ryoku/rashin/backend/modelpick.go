package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

type modelPicksFile struct {
	Picks map[string]string `json:"picks"`
}

var modelPicksMu sync.Mutex

func modelPicksPath() string {
	base := os.Getenv("RYOKU_STATE_PATH")
	if base == "" {
		base = os.Getenv("XDG_STATE_HOME")
		if base == "" {
			base = filepath.Join(home(), ".local", "state")
		}
		base = filepath.Join(base, "ryoku")
	}
	return filepath.Join(base, "rashin-models.json")
}

func legacyModelPickPath() string {
	return filepath.Join(filepath.Dir(modelPicksPath()), "rashin-model")
}

func readModelPicksLocked() modelPicksFile {
	var state modelPicksFile
	if data, err := os.ReadFile(modelPicksPath()); err == nil {
		if json.Unmarshal(data, &state) == nil && state.Picks != nil {
			_ = os.Remove(legacyModelPickPath())
			return state
		}
		return modelPicksFile{Picks: map[string]string{}}
	} else if !os.IsNotExist(err) {
		return modelPicksFile{Picks: map[string]string{}}
	}

	state.Picks = map[string]string{}
	legacy := legacyModelPickPath()
	data, err := os.ReadFile(legacy)
	if err != nil {
		return state
	}
	lines := strings.Split(string(data), "\n")
	if len(lines) >= 2 {
		id := strings.TrimSpace(lines[0])
		backend, _, ok := strings.Cut(strings.TrimSpace(lines[1]), "|")
		backend = strings.TrimSpace(backend)
		if ok && backend != "" && id != "" {
			state.Picks[backend] = id
			if writeModelPicksLocked(state) != nil {
				return modelPicksFile{Picks: map[string]string{}}
			}
		}
	}
	_ = os.Remove(legacy)
	return state
}

func writeModelPicksLocked(state modelPicksFile) error {
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return atomicWrite(modelPicksPath(), append(data, '\n'), 0o644)
}

func modelPick(backendID string) string {
	backendID = strings.TrimSpace(backendID)
	if backendID == "" {
		return ""
	}
	modelPicksMu.Lock()
	defer modelPicksMu.Unlock()
	return strings.TrimSpace(readModelPicksLocked().Picks[backendID])
}

func setModelPick(backendID, id string) error {
	backendID = strings.TrimSpace(backendID)
	id = strings.TrimSpace(id)
	if backendID == "" || id == "" {
		return errors.New("backend and model are required")
	}
	modelPicksMu.Lock()
	defer modelPicksMu.Unlock()
	state := readModelPicksLocked()
	state.Picks[backendID] = id
	return writeModelPicksLocked(state)
}

func (h *chatHub) applyModelPick(c *acpConn, id string) {
	if c == nil {
		return
	}
	if err := c.SetModel(id); err != nil {
		h.emitModelSwitchFailure(c, err)
		return
	}
	backendID := c.backend()
	if err := setModelPick(backendID, id); err != nil {
		h.emitModelSwitchFailure(c, err)
		return
	}
	c.emit(c.currentModelsEvent())

	for _, peer := range allHubs() {
		if peer == h {
			continue
		}
		peer.mu.Lock()
		other := peer.conn
		peer.mu.Unlock()
		if other == nil || other.backend() != backendID {
			continue
		}
		if err := other.SetModel(id); err != nil {
			peer.emitModelSwitchFailure(other, err)
			continue
		}
		other.emit(other.currentModelsEvent())
	}
}

func (h *chatHub) emitModelSwitchFailure(c *acpConn, err error) {
	h.mu.Lock()
	state := h.last
	h.mu.Unlock()
	reason := err.Error()
	for _, prefix := range []string{"acp session/set_model: ", "acp session/set_config_option: "} {
		if clean, ok := strings.CutPrefix(reason, prefix); ok {
			reason = clean
			break
		}
	}
	state.Type = "state"
	state.Error = "model switch failed: " + reason
	h.broadcast(state)
	c.emit(c.currentModelsEvent())
}
