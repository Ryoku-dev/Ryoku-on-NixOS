package main

import (
	"strings"
	"testing"
)

func TestParseTermArgsBufferMode(t *testing.T) {
	o, sub := parseTermArgs([]string{"--buffer", "--", "list files"})
	if !o.buffer || sub != "" || o.query != "list files" {
		t.Fatalf("parseTermArgs buffer = %+v sub=%q", o, sub)
	}
}

func TestParseTermArgsRejectsRetiredFishFlag(t *testing.T) {
	o, _ := parseTermArgs([]string{"--fish", "ask"})
	if o.buffer || o.query != "--fish ask" {
		t.Fatalf("retired --fish flag did not become query text: %+v", o)
	}
}

func TestPresenterNeedsAgentUsesAgentHandoff(t *testing.T) {
	p := &presenter{}
	p.line(`@answer {"id":"t1","text":"change the service","images":[],"actions":[],"via":"Hermes · Default","needsAgent":true,"needsAgentReason":"changing the service writes configuration"}`)
	if !p.needsAgent || p.needsAgentReason != "changing the service writes configuration" {
		t.Fatalf("presenter = %+v", p)
	}
	message := agentHandoffMessage(p.needsAgentReason)
	for _, want := range []string{"changing the service writes configuration", "Agent", "Alt+Space", "Agent tab"} {
		if !strings.Contains(message, want) {
			t.Fatalf("handoff message %q missing %q", message, want)
		}
	}
}
