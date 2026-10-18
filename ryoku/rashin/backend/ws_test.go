package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestTranscriptRecordsConversationOnly(t *testing.T) {
	h := newChatHub(ryokuLane())
	h.broadcast(wsOut{Type: "state", State: "busy"})
	h.broadcast(wsOut{Type: "user_text", Text: "q"})
	h.broadcast(wsOut{Type: "agent_text", Text: "a"})
	h.broadcast(wsOut{Type: "usage", Size: 10, Used: 1})
	h.broadcast(wsOut{Type: "tool", ID: "t1", Status: "completed"})
	h.broadcast(wsOut{Type: "turn_end", StopReason: "end_turn"})

	if len(h.transcript) != 4 {
		t.Fatalf("transcript = %d frames, want 4 (no state/usage)", len(h.transcript))
	}
	if h.transcript[0].Type != "user_text" || h.transcript[3].Type != "turn_end" {
		t.Fatalf("transcript order wrong: %+v", h.transcript)
	}
}

func TestTranscriptCapKeepsTail(t *testing.T) {
	h := newChatHub(ryokuLane())
	for i := range transcriptCap + 10 {
		h.broadcast(wsOut{Type: "tool", ID: fmt.Sprint("t", i), Status: "completed"})
	}
	if len(h.transcript) > transcriptCap {
		t.Fatalf("transcript grew past cap: %d", len(h.transcript))
	}
	if last := h.transcript[len(h.transcript)-1]; last.ID != fmt.Sprint("t", transcriptCap+9) {
		t.Fatalf("cap must keep the newest frames, last is %q", last.ID)
	}
}

// A joiner replays the conversation, not every chunk: a run of chunks is one
// frame and a tool call is one frame with its latest fields.
func TestTranscriptCoalescesChunksAndToolUpdates(t *testing.T) {
	h := newChatHub(ryokuLane())
	h.broadcast(wsOut{Type: "agent_thought", Text: "check "})
	h.broadcast(wsOut{Type: "agent_thought", Text: "logs"})
	h.broadcast(wsOut{Type: "tool", ID: "t1", Title: "$ journalctl -b", Kind: "execute", Status: "pending", Input: "journalctl -b", Auto: true})
	h.broadcast(wsOut{Type: "tool", ID: "t1", Status: "in_progress", Output: "line 1"})
	h.broadcast(wsOut{Type: "tool", ID: "t1", Status: "completed", Output: "line 1\nline 2"})
	h.broadcast(wsOut{Type: "agent_text", Text: "All "})
	h.broadcast(wsOut{Type: "agent_text", Text: "clear."})

	if len(h.transcript) != 3 {
		t.Fatalf("transcript = %d frames, want thought, tool, text: %+v", len(h.transcript), h.transcript)
	}
	if h.transcript[0].Text != "check logs" || h.transcript[2].Text != "All clear." {
		t.Fatalf("chunks not joined: %+v", h.transcript)
	}
	tool := h.transcript[1]
	if tool.Status != "completed" || tool.Output != "line 1\nline 2" || tool.Input != "journalctl -b" || !tool.Auto || tool.Title != "$ journalctl -b" {
		t.Fatalf("tool frame should carry its latest fields and keep the rest: %+v", tool)
	}
}

func TestOpenApprovalsTrackedApartFromTranscript(t *testing.T) {
	h := newChatHub(ryokuLane())
	h.broadcast(wsOut{Type: "permission", RequestID: "1", ToolID: "t1", Title: "rm x"})
	h.broadcast(wsOut{Type: "permission", RequestID: "2", ToolID: "t2", Title: "mv a b"})
	h.broadcast(wsOut{Type: "permission_resolved", RequestID: "1", Outcome: "allowed"})
	if len(h.transcript) != 0 {
		t.Fatalf("approvals are not conversation: %+v", h.transcript)
	}
	if len(h.perms) != 1 || h.perms[0].RequestID != "2" {
		t.Fatalf("open approvals = %+v, want only request 2", h.perms)
	}
	h.releasePerms()
	if len(h.perms) != 0 {
		t.Fatalf("a dead agent's approvals must be released: %+v", h.perms)
	}
}

func TestExtractImagesFindsRealFilesOnly(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	real := dir + "/shot.png"
	if err := writeFile(real, []byte("png")); err != nil {
		t.Fatal(err)
	}
	text := "Saved to " + real + " and also /nope/missing.png plus ~/shot.png"
	got := extractImages(text)
	if len(got) != 1 || got[0] != real {
		t.Fatalf("images = %v, want just %q", got, real)
	}
}

func writeFile(p string, b []byte) error {
	return atomicWrite(p, b, 0o644)
}

func TestExtractActionsKinds(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	file := dir + "/hypr.conf"
	if err := writeFile(file, []byte("x")); err != nil {
		t.Fatal(err)
	}
	text := "Edit " + file + " inside " + dir + " or see https://wiki.hyprland.org/Configuring." +
		" Run `ls -la` then use #C94E44 and `notarealbinary742 --x`."
	acts := extractActions(text)

	kinds := map[string]string{}
	for _, a := range acts {
		kinds[a.Kind] = a.Value
	}
	if kinds["file"] != file {
		t.Fatalf("file action = %q, want %q (all %+v)", kinds["file"], file, acts)
	}
	if kinds["dir"] != dir {
		t.Fatalf("dir action = %q, want %q", kinds["dir"], dir)
	}
	if kinds["url"] != "https://wiki.hyprland.org/Configuring" {
		t.Fatalf("url action = %q (trailing dot must be trimmed)", kinds["url"])
	}
	if kinds["cmd"] != "ls -la" {
		t.Fatalf("cmd action = %q", kinds["cmd"])
	}
	if kinds["color"] != "#C94E44" {
		t.Fatalf("color action = %q", kinds["color"])
	}
	for _, a := range acts {
		if strings.Contains(a.Value, "notarealbinary742") {
			t.Fatalf("fake binary must not become a cmd action: %+v", a)
		}
	}
}

func TestExtractActionsMissingPathsSkipped(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	acts := extractActions("look at /definitely/not/here.conf")
	if len(acts) != 0 {
		t.Fatalf("nonexistent path must yield no action: %+v", acts)
	}
}

func TestAskLaneRejectedFromChatSocket(t *testing.T) {
	quickTestEnv(t)
	old := laneHubs
	laneHubs = map[string]*chatHub{
		laneRyoku: newChatHub(ryokuLane()),
		laneChat:  newChatHub(chatLane()),
		laneAsk:   newChatHub(askLane()),
	}
	t.Cleanup(func() { laneHubs = old })
	req := httptest.NewRequest(http.MethodGet, "/ws/chat?lane=ask", nil)
	res := httptest.NewRecorder()
	handleChatWS(res, req)
	if res.Code != http.StatusBadRequest || strings.TrimSpace(res.Body.String()) != "unknown lane" {
		t.Fatalf("status = %d body = %q", res.Code, res.Body.String())
	}
	if _, ok := publicLaneHub(""); !ok {
		t.Fatal("an absent lane must still select Agent")
	}
}
