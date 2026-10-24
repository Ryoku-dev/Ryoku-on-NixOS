package main

import (
	"encoding/json"
	"testing"
)

func TestSplitHandoffBlockRoundTrip(t *testing.T) {
	question := "Why did it stop?"
	answer := "It ended after ] marker.\n[/handoff]\n\nThis is still inside the answer."
	text := "Please fix it."
	block := formatHandoffBlock(question, answer, text)
	q, a, rest, ok := splitHandoffBlock(block)
	if !ok || q != question || a != answer || rest != text {
		t.Fatalf("split = %q %q %q %v", q, a, rest, ok)
	}
	q, a, rest, ok = splitHandoffBlock("[system: private note] " + block)
	if !ok || q != question || a != answer || rest != text {
		t.Fatalf("split after identity = %q %q %q %v", q, a, rest, ok)
	}
}

func TestPendingHandoffPrefixesNextPromptOnce(t *testing.T) {
	h := newChatHub(lane{Name: laneRyoku, Intro: func() string { return "[system: note] " }})
	client := &chatClient{out: make(chan wsOut, 4)}
	h.mu.Lock()
	h.clients[client] = true
	h.mu.Unlock()

	h.handleHandoff(wsIn{Type: "handoff", AskID: "a1", Question: "Question", Answer: "Answer"}, client)
	card := <-client.out
	if card.Type != "handoff" || card.AskID != "a1" || card.Text != "Question" || card.Answer != "Answer" {
		t.Fatalf("card = %+v", card)
	}
	want := "[system: note] " + formatHandoffBlock("Question", "Answer", "Continue here")
	if got := h.userPrompt("Continue here"); got != want {
		t.Fatalf("first prompt = %q, want %q", got, want)
	}
	if got := h.userPrompt("Next"); got != "Next" {
		t.Fatalf("handoff repeated in next prompt: %q", got)
	}
	if len(h.transcript) != 1 || h.transcript[0].Type != "handoff" {
		t.Fatalf("transcript = %+v", h.transcript)
	}
}

func TestHandoffUsesAskHistoryByID(t *testing.T) {
	quickTestEnv(t)
	rec := makeAskRecord("a-history", "", "Stored question", "Stored answer", "Prowl · model", "")
	recordAsk(rec)
	h := newChatHub(lane{Name: laneRyoku, Intro: func() string { return "" }})
	client := &chatClient{out: make(chan wsOut, 2)}
	h.mu.Lock()
	h.clients[client] = true
	h.mu.Unlock()
	h.handleHandoff(wsIn{
		Type: "handoff", AskID: rec.ID, Question: "Wrong question", Answer: "Wrong answer",
	}, client)
	card := <-client.out
	if card.Text != rec.Question || card.Answer != rec.Answer {
		t.Fatalf("history handoff = %+v, want %+v", card, rec)
	}
}

func TestRunHandoffPromptsImmediately(t *testing.T) {
	quickTestEnv(t)
	conn, fa := newTestPair(t)
	defer conn.Close()
	conn.mu.Lock()
	conn.sessionID = "s1"
	conn.sessionReady = true
	conn.configStamp = hermesConfigStamp()
	conn.mu.Unlock()
	h := newChatHub(lane{Name: laneRyoku, Intro: func() string { return "" }})
	h.conn = conn
	client := &chatClient{out: make(chan wsOut, 4)}
	h.clients[client] = true
	cancelled := make(chan struct{})
	askHub := newChatHub(askLane())
	askHub.askCancel = func() { close(cancelled) }
	oldHubs := laneHubs
	laneHubs = map[string]*chatHub{laneRyoku: h, laneAsk: askHub}
	t.Cleanup(func() {
		h.mu.Lock()
		h.conn = nil
		h.mu.Unlock()
		laneHubs = oldHubs
	})

	h.handleHandoff(wsIn{Type: "handoff", AskID: "a2", Question: "Do the work", Run: true}, client)
	select {
	case <-cancelled:
	default:
		t.Fatal("run handoff did not cancel the in-flight Ask")
	}
	prompt := fa.read()
	if prompt.Method != "session/prompt" {
		t.Fatalf("method = %q, want session/prompt", prompt.Method)
	}
	var params struct {
		Prompt []struct {
			Text string `json:"text"`
		} `json:"prompt"`
	}
	if err := json.Unmarshal(prompt.Params, &params); err != nil || len(params.Prompt) != 1 {
		t.Fatalf("prompt params = %s, %v", prompt.Params, err)
	}
	want := formatHandoffBlock("Do the work", "", "Do the work")
	if params.Prompt[0].Text != want {
		t.Fatalf("prompt = %q, want %q", params.Prompt[0].Text, want)
	}
	if card, user, state := <-client.out, <-client.out, <-client.out; card.Type != "handoff" ||
		user.Type != "user_text" || state.Type != "state" || state.State != "busy" {
		t.Fatalf("frames = %+v, %+v, %+v", card, user, state)
	}
	fa.respond(*prompt.ID, map[string]string{"stopReason": "end_turn"})
	if len(h.transcript) != 2 || h.transcript[0].Type != "handoff" || h.transcript[1].Type != "user_text" {
		t.Fatalf("transcript = %+v", h.transcript)
	}
}

func TestReplayHandoffEmitsCardThenUserText(t *testing.T) {
	conn, _ := newTestPair(t)
	defer conn.Close()
	text := needleIdentity + formatHandoffBlock("Question", "Answer ] still answer", "Continue")
	params, _ := json.Marshal(map[string]any{
		"sessionId": "s1",
		"update": map[string]any{
			"sessionUpdate": "user_message_chunk",
			"content":       map[string]string{"type": "text", "text": text},
		},
	})
	conn.handleUpdate(params)
	card := expectEvent(t, conn.Events(), "handoff")
	if card.Text != "Question" || card.Answer != "Answer ] still answer" {
		t.Fatalf("handoff replay = %+v", card)
	}
	user := expectEvent(t, conn.Events(), "user_text")
	if user.Text != "Continue" {
		t.Fatalf("user replay = %q", user.Text)
	}
	if title := cleanTitle(text); title != "Continue" {
		t.Fatalf("cleanTitle = %q", title)
	}
}
