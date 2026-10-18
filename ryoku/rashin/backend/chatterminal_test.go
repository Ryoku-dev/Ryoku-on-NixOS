package main

import (
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestResumeArgvPerBackend(t *testing.T) {
	home := t.TempDir()
	bin := filepath.Join(home, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	hermes := filepath.Join(bin, "hermes")
	if err := os.WriteFile(hermes, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", bin)
	cases := []struct {
		backend string
		want    []string
	}{
		{"hermes", []string{hermes, "--resume", "s1"}},
		{"omp", []string{"omp", "--resume=s1"}},
		{"claude", []string{"claude", "--resume", "s1"}},
		{"codex", []string{"codex", "resume", "s1"}},
	}
	for _, test := range cases {
		t.Run(test.backend, func(t *testing.T) {
			got, err := resumeArgv(test.backend, "s1")
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, test.want) {
				t.Fatalf("argv = %v, want %v", got, test.want)
			}
		})
	}
}

func TestPlanChatTerminalConflicts(t *testing.T) {
	if _, err := planChatTerminal(nil); err == nil {
		t.Fatal("nil hub should report no session")
	} else {
		var conflict chatTerminalConflict
		if !errors.As(err, &conflict) {
			t.Fatalf("no-session error type = %T", err)
		}
	}
	h := &chatHub{
		lane: lane{Cwd: "/tmp/chat"},
		conn: &acpConn{agentID: "opencode", sessionID: "s1", sessionReady: true},
	}
	if _, err := planChatTerminal(h); err == nil {
		t.Fatal("unsupported backend should conflict")
	}
	h.conn.sessionID = ""
	h.conn.sessionReady = false
	if _, err := planChatTerminal(h); err == nil {
		t.Fatal("empty session should conflict")
	}
}

func TestHandleChatTerminalConflictAndLaunch(t *testing.T) {
	previousHubs := laneHubs
	previousLauncher := chatTerminalLauncher
	t.Cleanup(func() {
		laneHubs = previousHubs
		chatTerminalLauncher = previousLauncher
	})
	hub := &chatHub{
		lane:    lane{Name: laneRyoku, Cwd: "/tmp/vault"},
		clients: map[*chatClient]bool{},
	}
	laneHubs = map[string]*chatHub{laneRyoku: hub}
	request := httptest.NewRequest(http.MethodPost, "/api/chat/terminal?lane=ryoku", nil)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handleChatTerminal(response, request)
	if response.Code != http.StatusConflict {
		t.Fatalf("no-session status = %d body=%q", response.Code, response.Body.String())
	}

	hub.conn = &acpConn{agentID: "opencode", sessionID: "s1", sessionReady: true}
	response = httptest.NewRecorder()
	handleChatTerminal(response, request)
	if response.Code != http.StatusConflict {
		t.Fatalf("unsupported status = %d body=%q", response.Code, response.Body.String())
	}

	hub.conn = &acpConn{agentID: "codex", sessionID: "s1", sessionReady: true}
	var cwd, unit string
	var argv []string
	chatTerminalLauncher = func(gotCwd, gotUnit string, gotArgv []string) error {
		cwd, unit = gotCwd, gotUnit
		argv = append([]string(nil), gotArgv...)
		return nil
	}
	response = httptest.NewRecorder()
	handleChatTerminal(response, request)
	if response.Code != http.StatusNoContent {
		t.Fatalf("launch status = %d body=%q", response.Code, response.Body.String())
	}
	if cwd != "/tmp/vault" || unit != "ryoku-rashin-" ||
		!reflect.DeepEqual(argv, []string{"codex", "resume", "s1"}) {
		t.Fatalf("launch cwd=%q unit=%q argv=%v", cwd, unit, argv)
	}
}

func TestHandleChatTerminalRejectsUntrustedBrowserPosts(t *testing.T) {
	for _, test := range []struct {
		name        string
		origin      string
		contentType string
	}{
		{name: "foreign origin", origin: "https://example.com", contentType: "application/json"},
		{name: "simple content type", origin: "http://127.0.0.1:3600", contentType: "text/plain"},
		{name: "missing content type"},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/api/chat/terminal?lane=ryoku", nil)
			request.Header.Set("Origin", test.origin)
			request.Header.Set("Content-Type", test.contentType)
			response := httptest.NewRecorder()
			handleChatTerminal(response, request)
			if response.Code != http.StatusForbidden {
				t.Fatalf("status = %d body=%q", response.Code, response.Body.String())
			}
		})
	}
}

func TestCmdChatTerminalReportsDaemonConflict(t *testing.T) {
	quickTestEnv(t)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/chat/terminal" || r.URL.Query().Get("lane") != laneChat {
			http.NotFound(w, r)
			return
		}
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("content type = %q", r.Header.Get("Content-Type"))
		}
		http.Error(w, "this agent cannot resume sessions in a terminal", http.StatusConflict)
	}))
	defer server.Close()
	port := server.Listener.Addr().(*net.TCPAddr).Port
	cfg := LoadConfig()
	cfg.Port = port
	if err := SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}
	err := cmdChatTerminal([]string{"--lane", laneChat})
	if err == nil || err.Error() != "this agent cannot resume sessions in a terminal" {
		t.Fatalf("terminal conflict = %v", err)
	}
}
