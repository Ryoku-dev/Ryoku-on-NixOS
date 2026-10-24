package main

import (
	"encoding/json"
	"strings"
	"testing"

	wm "ryoku-wm"
)

// The emitted command line IS the contract with the compositor: mango ignores
// an unknown query and answers errors as JSON with a zero exit, so a wrong
// shape fails silently at runtime and these cases catch it at build time.
// The reply shapes are captured verbatim from a live 0.17.4 instance.

func TestWireEmitsMangoCommands(t *testing.T) {
	var got []string
	restore := stubRequest(t, func(cmd string) (json.RawMessage, error) {
		got = append(got, cmd)
		return json.RawMessage(`{"success":true}`), nil
	})
	defer restore()

	if err := dispatch("killclient", clientSuffix(375)); err != nil {
		t.Fatal(err)
	}
	if err := get("all-monitors", &monitorsEnvelope{}); err != nil {
		t.Fatal(err)
	}
	if err := dispatch("setoption", "focuscolor", "0xc9b890ff"); err != nil {
		t.Fatal(err)
	}
	if err := dispatch("focusid", "client", "375"); err != nil {
		t.Fatal(err)
	}

	want := []string{
		"dispatch killclient,client,375",
		"get all-monitors",
		"dispatch setoption,focuscolor,0xc9b890ff",
		"dispatch focusid,client,375",
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("emitted:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

// unwrap must surface mango's own error wording, never a silent nil: every IPC
// error arrives as JSON with a zero process exit, so this is the only gate.
func TestWireUnwrapPassesErrors(t *testing.T) {
	_, err := unwrap("dispatch nope", []byte(`{"error":"unknown function"}`))
	if err == nil || !strings.Contains(err.Error(), "unknown function") {
		t.Fatalf("want the compositor's own wording, got %v", err)
	}
	if _, err := unwrap("get focusing-client", []byte(`{"id":1}`)); err != nil {
		t.Fatalf("a good reply must pass: %v", err)
	}
	if _, err := unwrap("get version", []byte("not json")); err == nil {
		t.Fatal("want an error on a non-JSON line")
	}
}

// The captured live replies must decode into the provider's shapes: a field
// renamed upstream reads here first, not in a session that trusts it.
func TestWireDecodesLiveReplies(t *testing.T) {
	monitorLine := `{"monitors":[{"name":"HEADLESS-1","active":true,"is_hdr":false,"is_vrr":false,"x":0,"y":0,"width":1280,"height":720,"scale":1,"layout_index":0,"layout_symbol":"T","last_open_surface":"","tag_num":9,"hide_clients":0,"tags":[{"index":1,"is_active":true,"is_urgent":false,"layout":"T","client_count":1}]}]}`
	var mons monitorsEnvelope
	if err := json.Unmarshal([]byte(monitorLine), &mons); err != nil {
		t.Fatal(err)
	}
	m := mons.Monitors[0]
	if m.Name != "HEADLESS-1" || !m.Active || m.Width != 1280 || m.Scale != 1 || len(m.Tags) != 1 {
		t.Fatalf("decoded monitor wrong: %+v", m)
	}
	if m.Tags[0].Index != 1 || !m.Tags[0].IsActive || m.Tags[0].ClientCount != 1 || m.Tags[0].Layout != "T" {
		t.Fatalf("decoded tag wrong: %+v", m.Tags[0])
	}

	clientLine := `{"clients":[{"id":1,"pid":3232333,"foreign_toplevel_id":"013d","title":"foot","appid":"kitty","monitor":"HEADLESS-1","tags":[2],"is_xwayland":false,"is_visible":true,"is_focused":true,"is_fullscreen":false,"is_floating":false,"is_maximized":false,"is_urgent":false,"is_minimized":false,"is_scratchpad":false,"x":10,"y":10,"width":1260,"height":700,"scroller_proportion":0.8}]}`
	var clients clientsEnvelope
	if err := json.Unmarshal([]byte(clientLine), &clients); err != nil {
		t.Fatal(err)
	}
	c := clients.Clients[0]
	if c.ID != 1 || c.Title != "foot" || c.AppID != "kitty" || !c.IsFocused || c.X != 10 || c.Width != 1260 {
		t.Fatalf("decoded client wrong: %+v", c)
	}
	if len(c.Tags) != 1 || c.Tags[0] != 2 {
		t.Fatalf("decoded client tags wrong: %v", c.Tags)
	}

	layoutLine := `{"layouts":[{"symbol":"T","name":"tile"},{"symbol":"S","name":"scroller"}]}`
	var layouts layoutEnvelope
	if err := json.Unmarshal([]byte(layoutLine), &layouts); err != nil {
		t.Fatal(err)
	}
	names := layoutNames(layouts)
	if names["T"] != "tile" || names["S"] != "scroller" {
		t.Fatalf("layout symbol table wrong: %v", names)
	}

	kbLine := `{"layout":"English (US)"}`
	var kb struct {
		Layout string `json:"layout"`
	}
	if err := json.Unmarshal([]byte(kbLine), &kb); err != nil || kb.Layout != "English (US)" {
		t.Fatalf("keyboard reply wrong: %v %q", err, kb.Layout)
	}
}

// The watch grammar is pinned to the per-target lines mango's parser reads:
// one command per wanted stream kind.
func TestWatchEmitsPerTargetCommands(t *testing.T) {
	specs := streamsFor(func(wm.FrameKind) bool { return true })
	want := []string{"watch all-monitors", "watch all-clients", "watch keyboardlayout"}
	if len(specs) != len(want) {
		t.Fatalf("stream count %d, want %d", len(specs), len(want))
	}
	for i, s := range specs {
		if s.cmd != want[i] {
			t.Fatalf("stream %d cmd = %q, want %q", i, s.cmd, want[i])
		}
	}
	// A consumer that only wants outputs must not make mango answer windows.
	only := streamsFor(func(k wm.FrameKind) bool { return k == wm.FrameOutputs })
	if len(only) != 1 || only[0].cmd != "watch all-monitors" {
		t.Fatalf("narrowed watch wrong: %+v", only)
	}
}

// stubRequest swaps the compositor call and satisfies live(), which every
// action checks before dispatching: the handle env var names a fake socket,
// an aliveCheck that always answers dials nothing, and the request var pins
// the emitted line instead.
func stubRequest(t *testing.T, fn func(string) (json.RawMessage, error)) func() {
	t.Helper()
	prevRequest, prevLive := request, aliveCheck
	t.Setenv("MANGO_INSTANCE_SIGNATURE", "/fake/mango-1.sock")
	request = func(cmd string) (json.RawMessage, error) { return fn(cmd) }
	aliveCheck = func(string) bool { return true }
	return func() { request, aliveCheck = prevRequest, prevLive }
}
