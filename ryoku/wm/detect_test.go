package wm

import (
	"net"
	"os"
	"path/filepath"
	"testing"
)

// LeafScriptsDir is the single definition of where a provider's bare-name
// scripts live; deploy.sh and the switch resolve them through it, so a wrong
// or empty path silently strands a compositor's display or workspace tools.
func TestLeafScriptsDir(t *testing.T) {
	if got, want := LeafScriptsDir(ProviderHyprland), "ryoku/hyprland/scripts"; got != want {
		t.Errorf("hyprland = %q, want %q", got, want)
	}
	if got, want := LeafScriptsDir(ProviderNiri), "ryoku/niri/scripts"; got != want {
		t.Errorf("niri = %q, want %q", got, want)
	}
	if got := LeafScriptsDir(""); got != "" {
		t.Errorf("empty name = %q, want empty", got)
	}
}

// SessionGap is the switch's honesty gate: a checkout box has every provider's
// binary and config tree, but only a session the greeter can actually boot is
// switchable. The gap must name the missing half, and a provider with both
// halves must report none.
func TestSessionGap(t *testing.T) {
	bin := t.TempDir()
	niri := filepath.Join(bin, "niri")
	if err := os.WriteFile(niri, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)

	entries := t.TempDir()
	if err := os.WriteFile(filepath.Join(entries, "niri.desktop"), []byte("[Desktop Entry]\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	orig := sessionEntryDirs
	t.Cleanup(func() { sessionEntryDirs = orig })
	sessionEntryDirs = func() []string { return []string{entries} }

	if got := SessionGap(ProviderNiri); got != "" {
		t.Errorf("installed compositor + entry = %q, want ready", got)
	}
	if got := SessionGap("nobody"); got != "compositor" {
		t.Errorf("unknown provider = %q, want compositor (no binary named)", got)
	}

	// The entry disappears: the greeter has nothing to offer.
	os.Remove(filepath.Join(entries, "niri.desktop"))
	if got := SessionGap(ProviderNiri); got != "entry" {
		t.Errorf("compositor without a session entry = %q, want entry", got)
	}

	// The compositor disappears: the entry would launch nothing.
	os.WriteFile(filepath.Join(entries, "niri.desktop"), []byte("[Desktop Entry]\n"), 0o644)
	t.Setenv("PATH", t.TempDir())
	if got := SessionGap(ProviderNiri); got != "compositor" {
		t.Errorf("entry without a compositor = %q, want compositor", got)
	}
}

func TestDetectUsesLiveSystemdManagerHandle(t *testing.T) {
	for _, key := range SessionHandles() {
		t.Setenv(key, "")
	}
	t.Setenv("RYOKU_WM", "")
	t.Setenv("XDG_CURRENT_DESKTOP", "")

	sock := filepath.Join(t.TempDir(), "niri.sock")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	orig := managerEnvironment
	t.Cleanup(func() { managerEnvironment = orig })
	managerEnvironment = func() map[string]string {
		return map[string]string{"NIRI_SOCKET": sock}
	}

	got := Detect()
	if got.Name != ProviderNiri || !got.Live || got.Source != "systemd:NIRI_SOCKET" {
		t.Fatalf("Detect() = %+v, want live niri from systemd manager environment", got)
	}
}
