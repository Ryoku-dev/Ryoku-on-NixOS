package main

import (
	"strings"
	"testing"
)

// A bare agent error is only half the story: hermes writes the real cause to
// its own stderr. The request error must ride that tail along so the chat
// banner and `ryoku-rashin logs` name what actually broke.
func TestACPErrorCarriesStderrTail(t *testing.T) {
	conn, fa := newTestPair(t)
	conn.errTail = newTailBuffer(acpStderrTailBytes)
	conn.errTail.Write([]byte("boot noise\n2026-10-03 [ERROR] provider auth failed: 401\n"))

	go func() {
		m := fa.read()
		fa.write(rpcMsg{JSONRPC: "2.0", ID: m.ID,
			Error: &rpcError{Code: -32603, Message: "Internal error"}})
	}()

	_, err := conn.request("session/new", map[string]any{"cwd": "/tmp"})
	if err == nil {
		t.Fatal("session/new error response produced no error")
	}
	msg := err.Error()
	if !strings.Contains(msg, "Internal error") {
		t.Fatalf("error lost the agent message: %q", msg)
	}
	if !strings.Contains(msg, "provider auth failed: 401") {
		t.Fatalf("error lost the stderr cause: %q", msg)
	}
}

// With no tail (a test pair, or an agent that logged nothing), the error is
// exactly what it was before: no dangling separator.
func TestACPErrorWithoutTailUnchanged(t *testing.T) {
	conn, fa := newTestPair(t)
	go func() {
		m := fa.read()
		fa.write(rpcMsg{JSONRPC: "2.0", ID: m.ID,
			Error: &rpcError{Code: -32603, Message: "Internal error"}})
	}()
	_, err := conn.request("session/new", map[string]any{"cwd": "/tmp"})
	if err == nil || err.Error() != "acp session/new: Internal error" {
		t.Fatalf("error = %v, want the bare message", err)
	}
}
