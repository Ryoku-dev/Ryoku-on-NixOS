package main

import (
	"encoding/json"
	"testing"
)

// These frames are the ones `omp acp` sends: tool content as a list of
// blocks, the approval request before the tool_call, and models offered as a
// select config option rather than the legacy models block.

func startOmpSession(t *testing.T) (*acpConn, *fakeAgent) {
	t.Helper()
	conn, fa := newTestPair(t)
	done := make(chan error, 1)
	go func() { done <- conn.Initialize("/tmp/vault") }()
	init := fa.read()
	fa.respond(*init.ID, map[string]any{"protocolVersion": 1})
	newSess := fa.read()
	fa.respond(*newSess.ID, map[string]any{
		"sessionId": "s1",
		"configOptions": []map[string]any{
			{"id": "mode", "category": "mode", "type": "select", "currentValue": "default",
				"options": []map[string]string{{"value": "default", "name": "Default"}}},
			{"id": "model", "category": "model", "type": "select", "currentValue": "anthropic/claude-opus-5-5",
				"options": []map[string]string{
					{"value": "anthropic/claude-opus-5-5", "name": "Claude Opus 5.5", "description": "anthropic/claude-opus-5-5"},
					{"value": "anthropic/claude-haiku-4-5", "name": "Claude Haiku 4.5", "description": "anthropic/claude-haiku-4-5"},
				}},
		},
	})
	if err := <-done; err != nil {
		t.Fatalf("Initialize: %v", err)
	}
	return conn, fa
}

func requestPermission(fa *fakeAgent, id int64, call map[string]any) {
	p, _ := json.Marshal(map[string]any{
		"sessionId": "s1",
		"toolCall":  call,
		"options": []map[string]string{
			{"optionId": "allow_once", "name": "Allow once", "kind": "allow_once"},
			{"optionId": "allow_always", "name": "Always allow", "kind": "allow_always"},
			{"optionId": "reject_once", "name": "Reject", "kind": "reject_once"},
		},
	})
	fa.write(rpcMsg{JSONRPC: "2.0", ID: &id, Method: "session/request_permission", Params: p})
}

func TestACPConfigOptionModels(t *testing.T) {
	conn, fa := startOmpSession(t)
	defer conn.Close()

	ev := expectEvent(t, conn.Events(), "models")
	if ev.CurrentModel != "anthropic/claude-opus-5-5" || len(ev.Models) != 2 || ev.Models[1].Name != "Claude Haiku 4.5" {
		t.Fatalf("models from configOptions: %+v", ev)
	}
	if ev.Models[0].Description != "" {
		t.Fatalf("a description that only repeats the id should be dropped: %q", ev.Models[0].Description)
	}

	done := make(chan error, 1)
	go func() { done <- conn.SetModel("anthropic/claude-haiku-4-5") }()
	req := fa.read()
	var p struct {
		ConfigID string `json:"configId"`
		Value    string `json:"value"`
	}
	_ = json.Unmarshal(req.Params, &p)
	if req.Method != "session/set_config_option" || p.ConfigID != "model" || p.Value != "anthropic/claude-haiku-4-5" {
		t.Fatalf("model switch went out as %s %+v", req.Method, p)
	}
	fa.respond(*req.ID, map[string]any{})
	if err := <-done; err != nil {
		t.Fatalf("SetModel: %v", err)
	}
}

func TestACPToolContentListCarriesOutput(t *testing.T) {
	conn, fa := startOmpSession(t)
	defer conn.Close()
	expectEvent(t, conn.Events(), "models")

	fa.update("s1", map[string]any{
		"sessionUpdate": "tool_call", "toolCallId": "t1", "title": "$ uname -r", "kind": "execute",
		"status": "pending", "rawInput": map[string]string{"command": "uname -r"},
		"content": []map[string]any{{"type": "content", "content": map[string]string{"type": "text", "text": "$ uname -r"}}},
	})
	fa.update("s1", map[string]any{
		"sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed",
		"rawOutput": map[string]any{"content": []map[string]string{{"type": "text", "text": "7.2.7-arch1-1\n"}}},
		"content": []map[string]any{
			{"type": "content", "content": map[string]string{"type": "text", "text": "$ uname -r"}},
			{"type": "content", "content": map[string]string{"type": "text", "text": "7.2.7-arch1-1\n"}},
		},
	})
	fa.update("s1", map[string]any{
		"sessionUpdate": "tool_call_update", "toolCallId": "t2", "status": "completed",
		"content": []map[string]any{{"type": "diff", "path": "/tmp/a.conf", "oldText": "a=1\n", "newText": "a=2\n"}},
	})
	fa.update("s1", map[string]any{"sessionUpdate": "tool_call_update", "toolCallId": "t3"})

	first := expectEvent(t, conn.Events(), "tool")
	if first.Tool.Input != "uname -r" || first.Tool.Status != "pending" || first.Tool.Output != "" {
		t.Fatalf("the command echo is not output: %+v", first.Tool)
	}
	done := expectEvent(t, conn.Events(), "tool")
	if done.Tool.Status != "completed" || done.Tool.Output != "7.2.7-arch1-1" {
		t.Fatalf("a content list update must reach the UI with its output: %+v", done.Tool)
	}
	diff := expectEvent(t, conn.Events(), "tool")
	if len(diff.Tool.Diffs) != 1 || diff.Tool.Diffs[0].Path != "/tmp/a.conf" || diff.Tool.Diffs[0].New != "a=2\n" {
		t.Fatalf("diff block: %+v", diff.Tool)
	}
	bare := expectEvent(t, conn.Events(), "tool")
	if bare.Tool.Status != "" {
		t.Fatalf("an update without a status must leave it unchanged, got %q", bare.Tool.Status)
	}
}

func TestACPReadOnlyCallsRunUnasked(t *testing.T) {
	conn, fa := startOmpSession(t)
	defer conn.Close()
	expectEvent(t, conn.Events(), "models")

	requestPermission(fa, 5, map[string]any{
		"toolCallId": "t1", "title": "uname -r", "kind": "execute", "status": "pending",
		"rawInput": map[string]string{"command": "uname -r"},
	})
	resp := fa.read()
	var out struct {
		Outcome struct {
			Outcome  string `json:"outcome"`
			OptionID string `json:"optionId"`
		} `json:"outcome"`
	}
	_ = json.Unmarshal(resp.Result, &out)
	if resp.ID == nil || *resp.ID != 5 || out.Outcome.OptionID != "allow_once" {
		t.Fatalf("a read-only call should be allowed once by the daemon: %+v %+v", resp.ID, out)
	}
	ev := expectEvent(t, conn.Events(), "tool")
	if !ev.ToolAuto || ev.Tool.ID != "t1" || ev.Tool.Input != "uname -r" {
		t.Fatalf("auto-approved row: %+v", ev)
	}

	// Something that changes the machine still asks, with its row first.
	requestPermission(fa, 6, map[string]any{
		"toolCallId": "t2", "title": "rm -rf /tmp/x", "kind": "execute",
		"rawInput": map[string]string{"command": "rm -rf /tmp/x"},
	})
	row := expectEvent(t, conn.Events(), "tool")
	if row.ToolAuto || row.Tool.ID != "t2" {
		t.Fatalf("row before the approval: %+v", row)
	}
	perm := expectEvent(t, conn.Events(), "permission")
	if perm.RequestID != "6" || perm.Tool.ID != "t2" || perm.Tool.Input != "rm -rf /tmp/x" {
		t.Fatalf("approval must name its tool and command: %+v", perm)
	}

	// Cancelling the turn releases the open approval, as ACP requires.
	conn.Cancel()
	if m := fa.read(); m.Method != "session/cancel" {
		t.Fatalf("want session/cancel first, got %+v", m)
	}
	released := fa.read()
	_ = json.Unmarshal(released.Result, &out)
	if released.ID == nil || *released.ID != 6 || out.Outcome.Outcome != "cancelled" {
		t.Fatalf("open approval must be answered cancelled: %+v %+v", released.ID, out)
	}
	if ev := expectEvent(t, conn.Events(), "permission_resolved"); ev.Outcome != "cancelled" {
		t.Fatalf("resolved: %+v", ev)
	}
}

func TestACPAskModeAsksForReads(t *testing.T) {
	conn, fa := startOmpSession(t)
	defer conn.Close()
	expectEvent(t, conn.Events(), "models")
	cfg := LoadConfig()
	cfg.Approvals = approvalsAsk
	if err := SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}

	requestPermission(fa, 9, map[string]any{
		"toolCallId": "t1", "title": "uname -r", "kind": "execute",
		"rawInput": map[string]string{"command": "uname -r"},
	})
	expectEvent(t, conn.Events(), "tool")
	if ev := expectEvent(t, conn.Events(), "permission"); ev.RequestID != "9" {
		t.Fatalf("ask mode must ask: %+v", ev)
	}
}
