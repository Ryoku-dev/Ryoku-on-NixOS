package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPickBackend(t *testing.T) {
	backs := []chatBackend{
		{ID: "hermes", Name: "Hermes", Recommended: true},
		{ID: "claude", Name: "Claude Code"},
	}
	only := func(ids ...string) func(chatBackend) bool {
		set := map[string]bool{}
		for _, id := range ids {
			set[id] = true
		}
		return func(b chatBackend) bool { return set[b.ID] }
	}
	cases := []struct {
		name   string
		want   string
		avail  func(chatBackend) bool
		expect string
		ok     bool
	}{
		{"default falls to hermes", "", only("hermes", "claude"), "hermes", true},
		{"explicit available pick wins", "claude", only("hermes", "claude"), "claude", true},
		{"unavailable pick falls back to hermes", "claude", only("hermes"), "hermes", true},
		{"nothing available", "claude", only(), "", false},
		{"default with only a non-hermes agent", "", only("claude"), "claude", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			b, ok := pickBackend(c.want, backs, c.avail)
			if ok != c.ok || b.ID != c.expect {
				t.Fatalf("pickBackend(%q) = (%q,%v), want (%q,%v)", c.want, b.ID, ok, c.expect, c.ok)
			}
		})
	}
}

func TestChatBackendsOrderAndAdapters(t *testing.T) {
	home := t.TempDir()
	bin := filepath.Join(home, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"hermes", "codex-acp", "claude-agent-acp", "omp", "opencode", "gemini"} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", bin)
	backs := chatBackends()
	var ids []string
	for _, backend := range backs {
		ids = append(ids, backend.ID)
		if !chatBackendAvailable(backend) {
			t.Fatalf("%s should be available from temp PATH", backend.ID)
		}
	}
	if got := strings.Join(ids, ","); got != "hermes,codex,claude,omp,opencode,gemini" {
		t.Fatalf("backend order = %q", got)
	}
	if backs[1].Argv[0] != "codex-acp" || backs[2].Argv[0] != "claude-agent-acp" ||
		strings.Join(backs[5].Argv, " ") != "gemini --experimental-acp" {
		t.Fatalf("adapter argv = codex:%v claude:%v gemini:%v", backs[1].Argv, backs[2].Argv, backs[5].Argv)
	}
}

func TestSetChatAgentPersistsWithoutProwlCall(t *testing.T) {
	quickTestEnv(t)
	requests := 0
	quickGateway(t, func(w http.ResponseWriter, r *http.Request) {
		requests++
		http.Error(w, "must not be called", http.StatusInternalServerError)
	})
	if _, err := setChatAgent(context.Background(), "bogus"); err == nil {
		t.Fatal("unknown chat agent must error")
	}
	if _, err := setChatAgent(context.Background(), "gemini"); err != nil {
		t.Fatalf("Gemini should be accepted as a direct chat agent: %v", err)
	}
	if cfg := LoadConfig(); cfg.ChatAgent != "gemini" || len(cfg.ProwlHarnesses) != 0 {
		t.Fatalf("config after selecting Gemini = %+v", cfg)
	}
	if _, err := setChatAgent(context.Background(), "claude"); err != nil {
		t.Fatalf("Claude selection: %v", err)
	}
	if cfg := LoadConfig(); cfg.ChatAgent != "claude" || len(cfg.ProwlHarnesses) != 0 {
		t.Fatalf("config after selecting Claude = %+v", cfg)
	}
	if requests != 0 {
		t.Fatalf("setChatAgent made %d Prowl requests", requests)
	}
}

func TestChatModelProwlAlias(t *testing.T) {
	cases := []struct {
		name      string
		active    bool
		model     ModelInfo
		startedOn string
		want      bool
	}{
		{"Prowl provider id", false, ModelInfo{ID: "prowl:auto"}, "", true},
		{"custom Prowl provider id", false, ModelInfo{ID: "custom:prowl:auto"}, "", true},
		{"Prowl slash id", false, ModelInfo{ID: "prowl/auto"}, "", true},
		{"Prowl provider description", false, ModelInfo{ID: "custom:auto", Description: "Provider: PrOwL • current"}, "", true},
		{"active session starting model", true, ModelInfo{ID: "custom:auto"}, "custom:auto", true},
		{"pending session starting model", false, ModelInfo{ID: "custom:auto"}, "custom:auto", false},
		{"unmarked auto model", true, ModelInfo{ID: "custom:auto"}, "prowl:auto", false},
		{"direct model", true, ModelInfo{ID: "openai-codex:gpt-5.6-sol"}, "custom:auto", false},
		{"Prowl non-auto model", true, ModelInfo{ID: "prowl:manual"}, "", false},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if got := chatModelProwlAlias(test.active, test.model, test.startedOn); got != test.want {
				t.Fatalf("chatModelProwlAlias() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestUnwireActiveChatAgentIsAllowed(t *testing.T) {
	home := quickTestEnv(t)
	if err := os.MkdirAll(filepath.Join(home, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := LoadConfig()
	cfg.ChatAgent = "claude"
	cfg.ProwlHarnesses = []string{"claude"}
	if err := SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}
	quickGateway(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodDelete || r.URL.Path != "/api/setup/harnesses/claude" {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	request := httptest.NewRequest(http.MethodPost, "/api/agents/unwire", strings.NewReader(`{"id":"claude"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handleUnwireAgent(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", response.Code, response.Body.String())
	}
}

func TestOwnedMutationHandlersRejectForeignOrigins(t *testing.T) {
	for _, test := range []struct {
		name    string
		path    string
		body    string
		handler http.HandlerFunc
	}{
		{name: "wire", path: "/api/agents/wire", body: `{"id":"codex"}`, handler: handleWireAgent},
		{name: "unwire", path: "/api/agents/unwire", body: `{"id":"codex"}`, handler: handleUnwireAgent},
		{name: "default", path: "/api/agents/default", body: `{"id":"codex","prowl":false}`, handler: handleSetHarnessDefault},
		{name: "route", path: "/api/harnesses/route", body: `{}`, handler: handleRefreshHarnesses},
		{name: "chat agent", path: "/api/chat/agent?id=claude", handler: handleSetChatAgent},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, test.path, strings.NewReader(test.body))
			request.Header.Set("Origin", "https://example.com")
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			test.handler(response, request)
			if response.Code != http.StatusForbidden {
				t.Fatalf("status = %d body=%q", response.Code, response.Body.String())
			}
		})
	}
}

func TestSetChatAgentRejectsAnotherLoopbackOrigin(t *testing.T) {
	request := httptest.NewRequest(http.MethodPost, "/api/chat/agent?id=claude", nil)
	request.Host = "127.0.0.1:3600"
	request.Header.Set("Origin", "http://127.0.0.1:9999")
	response := httptest.NewRecorder()
	handleSetChatAgent(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d body=%q", response.Code, response.Body.String())
	}
}

func TestJSONMutationHandlersRejectSimpleContentTypes(t *testing.T) {
	for _, test := range []struct {
		name    string
		path    string
		handler http.HandlerFunc
	}{
		{name: "wire", path: "/api/agents/wire", handler: handleWireAgent},
		{name: "unwire", path: "/api/agents/unwire", handler: handleUnwireAgent},
		{name: "default", path: "/api/agents/default", handler: handleSetHarnessDefault},
		{name: "route", path: "/api/harnesses/route", handler: handleRefreshHarnesses},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, test.path, strings.NewReader(`{}`))
			request.Header.Set("Origin", "http://127.0.0.1:3600")
			request.Header.Set("Content-Type", "text/plain")
			response := httptest.NewRecorder()
			test.handler(response, request)
			if response.Code != http.StatusForbidden {
				t.Fatalf("status = %d body=%q", response.Code, response.Body.String())
			}
		})
	}
}

// The paste snippet is the whole point of "point any agent at Ryoku": it must
// name the vault, prowl, and the skill so an unsupported agent gets the
// same power. A regression that drops one silently weakens every such agent.
func TestManifestSnippet(t *testing.T) {
	h := t.TempDir()
	t.Setenv("XDG_DATA_HOME", filepath.Join(h, "data"))
	skill := filepath.Join(h, "skills", "ryoku")
	snip := manifestSnippet(skill)
	for _, want := range []string{
		"prowl", "AGENTS.md", filepath.Join(skill, "SKILL.md"), "ryoku-rashin",
	} {
		if !strings.Contains(snip, want) {
			t.Fatalf("snippet missing %q:\n%s", want, snip)
		}
	}
}

// vaultManifest lists the read-order docs; the index (AGENTS.md) must lead so an
// agent reads the map before anything else.
func TestVaultManifestOrder(t *testing.T) {
	items := vaultManifest()
	if len(items) == 0 || items[0].Label != "AGENTS.md" {
		t.Fatalf("vault manifest must lead with AGENTS.md, got %+v", items)
	}
	var haveDesktop bool
	for _, it := range items {
		if it.Label == "desktop.md" {
			haveDesktop = true
		}
	}
	if !haveDesktop {
		t.Fatal("vault manifest missing desktop.md")
	}
}
