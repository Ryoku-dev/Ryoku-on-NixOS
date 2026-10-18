package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func modelPickTestEnv(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	state := filepath.Join(home, "state")
	t.Setenv("HOME", home)
	t.Setenv("RYOKU_STATE_PATH", state)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, "config"))
	t.Setenv("RYOKU_CONFIG_BASE", filepath.Join(home, "packaged-absent"))
	return state
}

func TestModelPickStoredPerBackend(t *testing.T) {
	modelPickTestEnv(t)
	if err := setModelPick("hermes", "openai-codex:gpt-6-luna"); err != nil {
		t.Fatal(err)
	}
	if err := setModelPick("omp", "anthropic:opus"); err != nil {
		t.Fatal(err)
	}
	if got := modelPick("hermes"); got != "openai-codex:gpt-6-luna" {
		t.Fatalf("Hermes pick = %q", got)
	}
	if got := modelPick("omp"); got != "anthropic:opus" {
		t.Fatalf("omp pick = %q", got)
	}
	data, err := os.ReadFile(modelPicksPath())
	if err != nil {
		t.Fatal(err)
	}
	var state modelPicksFile
	if err := json.Unmarshal(data, &state); err != nil {
		t.Fatal(err)
	}
	if len(state.Picks) != 2 {
		t.Fatalf("stored picks = %+v", state.Picks)
	}
}

func TestModelPickMigratesLegacyFileOnce(t *testing.T) {
	state := modelPickTestEnv(t)
	if err := os.MkdirAll(state, 0o755); err != nil {
		t.Fatal(err)
	}
	legacy := filepath.Join(state, "rashin-model")
	if err := os.WriteFile(legacy, []byte("openai-codex:gpt-6-luna\nhermes|openrouter/old\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := modelPick("hermes"); got != "openai-codex:gpt-6-luna" {
		t.Fatalf("migrated pick = %q", got)
	}
	if _, err := os.Stat(legacy); !os.IsNotExist(err) {
		t.Fatalf("legacy file was not removed: %v", err)
	}
	if _, err := os.Stat(modelPicksPath()); err != nil {
		t.Fatalf("new pick file missing: %v", err)
	}
}

func modelPickConn(t *testing.T, backend, current string) (*acpConn, *fakeAgent) {
	t.Helper()
	conn, agent := newTestPair(t)
	conn.agentID = backend
	conn.agentName = backend
	conn.sessionID = "session-" + backend
	conn.sessionReady = true
	conn.currentModel = current
	conn.models = []ModelInfo{{ID: current, Name: current}, {ID: "openai-codex:gpt-6-luna", Name: "Luna"}}
	conn.offeredModels = append([]ModelInfo(nil), conn.models...)
	return conn, agent
}

func TestApplyModelPickPersistsAndPropagatesByBackend(t *testing.T) {
	modelPickTestEnv(t)
	first, firstAgent := modelPickConn(t, "hermes", "openai-codex:gpt-5.5")
	second, secondAgent := modelPickConn(t, "hermes", "openai-codex:gpt-5.5")
	other, otherAgent := modelPickConn(t, "omp", "openai-codex:gpt-5.5")
	defer first.Close()
	defer second.Close()
	defer other.Close()
	h1 := &chatHub{conn: first, clients: map[*chatClient]bool{}, last: wsOut{Type: "state", State: "ready"}}
	h2 := &chatHub{conn: second, clients: map[*chatClient]bool{}, last: wsOut{Type: "state", State: "ready"}}
	h3 := &chatHub{conn: other, clients: map[*chatClient]bool{}, last: wsOut{Type: "state", State: "ready"}}
	hubsMu.Lock()
	previous := hubs
	hubs = []*chatHub{h1, h2, h3}
	hubsMu.Unlock()
	t.Cleanup(func() {
		hubsMu.Lock()
		hubs = previous
		hubsMu.Unlock()
	})

	done := make(chan struct{})
	go func() {
		h1.applyModelPick(first, "openai-codex:gpt-6-luna")
		close(done)
	}()
	request := firstAgent.read()
	firstAgent.respond(*request.ID, map[string]any{})
	request = secondAgent.read()
	secondAgent.respond(*request.ID, map[string]any{})
	<-done

	if got := modelPick("hermes"); got != "openai-codex:gpt-6-luna" {
		t.Fatalf("stored pick = %q", got)
	}
	for _, conn := range []*acpConn{first, second} {
		event := expectEvent(t, conn.Events(), "models")
		if event.CurrentModel != "openai-codex:gpt-6-luna" || event.Pick != "openai-codex:gpt-6-luna" {
			t.Fatalf("propagated event = %+v", event)
		}
	}
	select {
	case request := <-otherAgent.lines:
		t.Fatalf("other backend received %s", request.Method)
	default:
	}
	if got := modelPick("omp"); got != "" {
		t.Fatalf("other backend pick = %q", got)
	}
}

func TestApplyModelPickFailureKeepsPickAndTrueCurrent(t *testing.T) {
	modelPickTestEnv(t)
	if err := setModelPick("hermes", "openai-codex:gpt-5.5"); err != nil {
		t.Fatal(err)
	}
	conn, agent := modelPickConn(t, "hermes", "openai-codex:gpt-5.5")
	defer conn.Close()
	hub := &chatHub{conn: conn, clients: map[*chatClient]bool{}, last: wsOut{Type: "state", State: "ready"}}
	done := make(chan struct{})
	go func() {
		hub.applyModelPick(conn, "openai-codex:gpt-6-luna")
		close(done)
	}()
	request := agent.read()
	agent.write(rpcMsg{JSONRPC: "2.0", ID: request.ID, Error: &rpcError{Code: -32000, Message: "rejected"}})
	<-done
	if got := modelPick("hermes"); got != "openai-codex:gpt-5.5" {
		t.Fatalf("failed pick changed stored value to %q", got)
	}
	event := expectEvent(t, conn.Events(), "models")
	if event.CurrentModel != "openai-codex:gpt-5.5" || event.Pick != "openai-codex:gpt-5.5" {
		t.Fatalf("failure event = %+v", event)
	}
	hub.mu.Lock()
	state := hub.last
	hub.mu.Unlock()
	if state.State != "ready" || state.Error != "model switch failed: rejected" {
		t.Fatalf("failure state = %+v", state)
	}
}
