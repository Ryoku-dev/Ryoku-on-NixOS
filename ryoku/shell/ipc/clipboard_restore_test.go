package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

// A daemon restart puts the last copy back only inside the compositor session
// that recorded it, only when there is something to put back, and never over a
// selection someone still owns. wl-paste is not asked unless the rest holds.
func TestShouldRestoreSelection(t *testing.T) {
	cases := []struct {
		name               string
		recorded, current  string
		haveEntry, empty   bool
		want, wantsPasting bool
	}{
		{"restart in the same session", "7:1.2", "7:1.2", true, true, true, true},
		{"a live copy still owned", "7:1.2", "7:1.2", true, false, false, true},
		{"new login or compositor", "7:1.2", "9:3.4", true, true, false, false},
		{"first daemon of the session", "", "9:3.4", true, true, false, false},
		{"no Wayland session", "", "", true, true, false, false},
		{"empty history", "7:1.2", "7:1.2", false, true, false, false},
	}
	for _, c := range cases {
		asked := false
		got := shouldRestoreSelection(c.recorded, c.current, c.haveEntry, func() bool {
			asked = true
			return c.empty
		})
		if got != c.want {
			t.Errorf("%s: restore = %v, want %v", c.name, got, c.want)
		}
		if asked != c.wantsPasting {
			t.Errorf("%s: asked wl-paste = %v, want %v", c.name, asked, c.wantsPasting)
		}
	}
}

func TestRestoreSelectionReadsPayloadFromDisk(t *testing.T) {
	runtimeDir := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	t.Setenv("WAYLAND_DISPLAY", "wayland-test")
	if err := os.WriteFile(filepath.Join(runtimeDir, "wayland-test"), []byte("socket"), 0o600); err != nil {
		t.Fatal(err)
	}
	current := clipSessionKey()
	if current == "" {
		t.Fatal("clipSessionKey returned empty")
	}
	if err := os.WriteFile(clipSessionPath(), []byte(current), 0o600); err != nil {
		t.Fatal(err)
	}

	bin := t.TempDir()
	copied := filepath.Join(t.TempDir(), "copied")
	writeCommandStub(t, bin, "wl-paste", "exit 1")
	writeCommandStub(t, bin, "wl-copy", `cat > "$CLIP_COPY_STDIN"`)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("CLIP_COPY_STDIN", copied)

	dataDir := filepath.Join(t.TempDir(), "data")
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		t.Fatal(err)
	}
	data := []byte("restored from disk")
	hash := clipHash(data)
	s := &clipState{
		dataDir: dataDir,
		entries: []*clipEntry{{
			ID: 1, Kind: "text", Mime: "text/plain", Size: len(data), hash: hash,
		}},
	}
	s.writeData(hash, data)
	s.restoreSelection()

	got, err := os.ReadFile(copied)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, data) {
		t.Errorf("restored payload = %q, want %q", got, data)
	}
}
