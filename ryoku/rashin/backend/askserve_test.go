package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAskFastLaneLeavesAgentHubUntouched(t *testing.T) {
	quickTestEnv(t)
	quickGateway(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/setup/harnesses":
			fmt.Fprint(w, `{"routable":true,"harnesses":[]}`)
		case "/api/profiles":
			fmt.Fprint(w, `[]`)
		case "/api/profiles/active":
			fmt.Fprint(w, `{"activeProfileId":null}`)
		case "/v1/chat/completions":
			writeSSE(w, "Isolated answer")
		default:
			http.NotFound(w, r)
		}
	})
	agentHub := newChatHub(ryokuLane())
	client := &chatClient{out: make(chan wsOut, 4)}
	agentHub.mu.Lock()
	agentHub.clients[client] = true
	agentHub.mu.Unlock()
	askHub := newChatHub(askLane())
	req := httptest.NewRequest(http.MethodPost, "/api/ask?q=hello", nil)
	res := httptest.NewRecorder()
	askHub.handleAsk(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
	for _, field := range []string{`"images":[]`, `"actions":[]`, `"needsAgent":false`, `"needsAgentReason":""`} {
		if !strings.Contains(res.Body.String(), field) {
			t.Fatalf("answer omitted %s: %s", field, res.Body.String())
		}
	}
	if len(agentHub.transcript) != 0 || len(client.out) != 0 {
		t.Fatalf("Agent changed: transcript=%+v queued=%d", agentHub.transcript, len(client.out))
	}
	var answer askAnswer
	for _, line := range strings.Split(res.Body.String(), "\n") {
		if strings.HasPrefix(line, "@answer ") {
			if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "@answer ")), &answer); err != nil {
				t.Fatal(err)
			}
		}
	}
	if answer.ID == "" || answer.Text != "Isolated answer" || answer.Via != "Prowl · gateway/model" {
		t.Fatalf("answer = %+v", answer)
	}
	recent := RecentAsks(1)
	if len(recent) != 1 || recent[0].ID != answer.ID || recent[0].Via != answer.Via {
		t.Fatalf("recent = %+v", recent)
	}
}

func TestAskWithoutAgentOrProwlExplainsRequirement(t *testing.T) {
	quickTestEnv(t)
	t.Setenv("PATH", t.TempDir())
	cfg := defaultConfig()
	cfg.Quick.Route = "agent"
	if err := SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}
	askHub := newChatHub(askLane())
	req := httptest.NewRequest(http.MethodPost, "/api/ask?q=hello", nil)
	res := httptest.NewRecorder()
	askHub.handleAsk(res, req)
	if body := res.Body.String(); !strings.Contains(body, "@error Ask needs an agent harness with an ACP adapter or a connected Prowl provider.") {
		t.Fatalf("response = %q", body)
	}
}

func TestAskHarnessResetWaitsForRunningAsk(t *testing.T) {
	h := newChatHub(askLane())
	conn := &acpConn{}
	h.conn = conn
	h.askRunning = true
	h.resetConn()
	h.mu.Lock()
	gotConn, deferred := h.conn, h.askReset
	h.mu.Unlock()
	conn.mu.Lock()
	closed := conn.closed
	conn.mu.Unlock()
	if gotConn != conn || !deferred || closed {
		t.Fatalf("conn=%p want=%p deferred=%v closed=%v", gotConn, conn, deferred, closed)
	}
}

func TestCancelledAskRetiresConnectionBeforeNextAsk(t *testing.T) {
	quickTestEnv(t)
	h := newChatHub(askLane())
	first, firstAgent := newTestPair(t)
	first.mu.Lock()
	first.cwd = h.lane.Cwd
	first.sessionID = "old"
	first.sessionReady = true
	first.configStamp = hermesConfigStamp()
	first.mu.Unlock()
	h.conn = first

	ctx, cancel := context.WithCancel(context.Background())
	firstDone := make(chan bool, 1)
	go func() {
		_, ok := h.sessionAsk(ctx, &askSink{w: httptest.NewRecorder(), f: httptest.NewRecorder()}, quickPreamble, "first")
		firstDone <- ok
	}()
	newSession := firstAgent.read()
	firstAgent.respond(*newSession.ID, map[string]any{"sessionId": "cancelled"})
	prompt := firstAgent.read()
	if prompt.Method != "session/prompt" {
		t.Fatalf("first prompt method = %q", prompt.Method)
	}
	cancel()
	select {
	case ok := <-firstDone:
		if ok {
			t.Fatal("cancelled ask reported success")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("cancelled ask did not stop")
	}
	firstAgent.update("cancelled", map[string]any{
		"sessionUpdate": "agent_message_chunk",
		"content":       map[string]string{"type": "text", "text": "stale answer"},
	})
	firstAgent.respond(*prompt.ID, map[string]string{"stopReason": "cancelled"})
	h.mu.Lock()
	if h.conn != nil {
		h.mu.Unlock()
		t.Fatal("cancelled Ask connection remained reusable")
	}
	h.mu.Unlock()

	second, secondAgent := newTestPair(t)
	defer second.Close()
	second.mu.Lock()
	second.cwd = h.lane.Cwd
	second.sessionID = "old2"
	second.sessionReady = true
	second.configStamp = hermesConfigStamp()
	second.mu.Unlock()
	h.mu.Lock()
	h.conn = second
	h.mu.Unlock()
	secondDone := make(chan sessionAskResult, 1)
	go func() {
		result, ok := h.sessionAsk(context.Background(), &askSink{w: httptest.NewRecorder(), f: httptest.NewRecorder()}, quickPreamble, "second")
		if !ok {
			t.Error("second ask failed")
		}
		secondDone <- result
	}()
	newSession = secondAgent.read()
	secondAgent.respond(*newSession.ID, map[string]any{"sessionId": "fresh"})
	prompt = secondAgent.read()
	secondAgent.update("fresh", map[string]any{
		"sessionUpdate": "agent_message_chunk",
		"content":       map[string]string{"type": "text", "text": "fresh answer"},
	})
	secondAgent.respond(*prompt.ID, map[string]string{"stopReason": "end_turn"})
	select {
	case result := <-secondDone:
		if result.Text != "fresh answer" {
			t.Fatalf("second answer = %q", result.Text)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("second ask did not finish")
	}
	h.resetConn()
}

func TestCompletedAskDrainsLateFramesBeforeReuse(t *testing.T) {
	quickTestEnv(t)
	h := newChatHub(askLane())
	conn, agent := newTestPair(t)
	defer conn.Close()
	conn.mu.Lock()
	conn.cwd = h.lane.Cwd
	conn.sessionID = "old"
	conn.sessionReady = true
	conn.configStamp = hermesConfigStamp()
	conn.mu.Unlock()
	h.conn = conn

	run := func(question, session, answer string) <-chan sessionAskResult {
		done := make(chan sessionAskResult, 1)
		go func() {
			out := httptest.NewRecorder()
			result, ok := h.sessionAsk(context.Background(), &askSink{w: out, f: out}, quickPreamble, question)
			if !ok {
				t.Errorf("%s ask failed", question)
			}
			done <- result
		}()
		newSession := agent.read()
		agent.respond(*newSession.ID, map[string]any{"sessionId": session})
		prompt := agent.read()
		agent.update(session, map[string]any{
			"sessionUpdate": "agent_message_chunk",
			"content":       map[string]string{"type": "text", "text": answer},
		})
		agent.respond(*prompt.ID, map[string]string{"stopReason": "end_turn"})
		return done
	}

	if result := <-run("first", "s1", "first answer"); result.Text != "first answer" {
		t.Fatalf("first answer = %q", result.Text)
	}
	conn.emit(AcpEvent{Type: "agent_text", Text: "stale answer"})
	conn.emit(AcpEvent{Type: "turn_end", StopReason: "end_turn"})
	if result := <-run("second", "s2", "fresh answer"); result.Text != "fresh answer" {
		t.Fatalf("second answer = %q", result.Text)
	}
	h.resetConn()
}

func TestBeginAskSessionRespawnsClosedConnection(t *testing.T) {
	quickTestEnv(t)
	h := newChatHub(askLane())
	replacement, agent := newTestPair(t)
	closed := &acpConn{closed: true, configStamp: hermesConfigStamp()}
	h.conn = closed
	previous := startAskACP
	startAskACP = func(string) (*acpConn, error) { return replacement, nil }
	t.Cleanup(func() { startAskACP = previous })

	done := make(chan *acpConn, 1)
	errs := make(chan error, 1)
	go func() {
		conn, err := h.beginAskSession(context.Background())
		done <- conn
		errs <- err
	}()
	initialize := agent.read()
	if initialize.Method != "initialize" {
		t.Fatalf("method = %q, want initialize", initialize.Method)
	}
	agent.respond(*initialize.ID, map[string]any{"protocolVersion": 1})
	newSession := agent.read()
	agent.respond(*newSession.ID, map[string]any{"sessionId": "fresh"})
	if err := <-errs; err != nil {
		t.Fatal(err)
	}
	if conn := <-done; conn != replacement {
		t.Fatalf("beginAskSession returned %p, want replacement %p", conn, replacement)
	}
	h.finishAskSession(replacement)
	h.resetConn()
}

func TestAskOnlyRejectsWriteAndReportsNeedsAgent(t *testing.T) {
	quickTestEnv(t)
	conn, fa := startOmpSession(t)
	defer conn.Close()
	conn.mu.Lock()
	conn.askOnly = true
	conn.mu.Unlock()
	expectEvent(t, conn.Events(), "models")
	var selected struct {
		Outcome struct {
			Outcome  string `json:"outcome"`
			OptionID string `json:"optionId"`
		} `json:"outcome"`
	}
	cfg := LoadConfig()
	cfg.Approvals = approvalsAsk
	if err := SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}
	requestPermission(fa, 40, map[string]any{
		"toolCallId": "read1", "title": "Read kernel", "kind": "execute",
		"rawInput": map[string]string{"command": "uname -r"},
	})
	readResp := fa.read()
	if err := json.Unmarshal(readResp.Result, &selected); err != nil {
		t.Fatal(err)
	}
	if selected.Outcome.OptionID != "allow_once" {
		t.Fatalf("read permission response = %+v", selected)
	}
	readTool := expectEvent(t, conn.Events(), "tool")
	if !readTool.ToolAuto {
		t.Fatalf("read tool was not auto-approved: %+v", readTool)
	}

	requestPermission(fa, 41, map[string]any{
		"toolCallId": "write1", "title": "Write /tmp/config", "kind": "edit",
		"rawInput": map[string]string{"path": "/tmp/config", "content": "changed"},
	})
	resp := fa.read()
	selected = struct {
		Outcome struct {
			Outcome  string `json:"outcome"`
			OptionID string `json:"optionId"`
		} `json:"outcome"`
	}{}
	if err := json.Unmarshal(resp.Result, &selected); err != nil {
		t.Fatal(err)
	}
	if selected.Outcome.Outcome != "selected" || selected.Outcome.OptionID != "reject_once" {
		t.Fatalf("permission response = %+v", selected)
	}
	expectEvent(t, conn.Events(), "tool")
	resolved := expectEvent(t, conn.Events(), "permission_resolved")
	if resolved.Outcome != "rejected" {
		t.Fatalf("resolved = %+v", resolved)
	}
	rec := makeAskRecord("a1", "", "change it", "", "Hermes · Default", conn.takeAskDenied())
	if !rec.NeedsAgent || rec.NeedsAgentReason != "Write /tmp/config" {
		t.Fatalf("record = %+v", rec)
	}
}

func TestAskToolInspectionFailsClosed(t *testing.T) {
	tests := []struct {
		name string
		call acpToolCall
		want bool
	}{
		{"empty read", acpToolCall{Kind: "read", Title: "Read defaults"}, false},
		{"malformed fetch", acpToolCall{Kind: "fetch", RawInput: json.RawMessage(`{"url":"not a url"}`)}, false},
		{"title-only execute", acpToolCall{Kind: "execute", Title: "uname -r"}, false},
		{"path read", acpToolCall{Kind: "read", RawInput: json.RawMessage(`{"path":"/etc/os-release"}`)}, true},
		{"http fetch", acpToolCall{Kind: "fetch", RawInput: json.RawMessage(`{"url":"https://example.com/"}`)}, true},
		{"raw execute", acpToolCall{Kind: "execute", RawInput: json.RawMessage(`{"command":"uname -r"}`)}, true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := askToolInspected(test.call); got != test.want {
				t.Fatalf("askToolInspected() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestNeedsAgentSentinelIsStripped(t *testing.T) {
	rec := makeAskRecord("a1", "", "change it", "NEEDS_AGENT: edit the service file and restart it", "Hermes · Model", "")
	if !rec.NeedsAgent || rec.Answer != "edit the service file and restart it" || rec.NeedsAgentReason != rec.Answer {
		t.Fatalf("record = %+v", rec)
	}
	if strings.Contains(mustAskJSON(rec), "NEEDS_AGENT:") {
		t.Fatal("sentinel leaked into @answer")
	}
}
