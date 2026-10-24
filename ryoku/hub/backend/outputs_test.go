package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	wm "ryoku-wm"
)

// TestPublishGreeterPrimary: the Displays apply records the layout's main output
// where the login greeter can read it. The page's "Set as main" re-bases the
// layout onto the chosen output, so the origin entry wins; a layout that
// predates that convention falls back to the top-left-most enabled output, and
// a disabled output at the origin is not the main.
func TestPublishGreeterPrimary(t *testing.T) {
	file := filepath.Join(t.TempDir(), "greeter-primary")
	t.Setenv("RYOKU_GREETER_PRIMARY_FILE", file)

	read := func() string {
		b, err := os.ReadFile(file)
		if err != nil {
			return ""
		}
		return strings.TrimSpace(string(b))
	}

	cases := []struct {
		name   string
		layout []wm.OutputLayout
		want   string
	}{
		{
			name: "origin is main",
			layout: []wm.OutputLayout{
				{Name: "HDMI-A-1", Enabled: true, X: 0, Y: 0},
				{Name: "eDP-1", Enabled: true, X: 1920, Y: 0},
			},
			want: "HDMI-A-1",
		},
		{
			name: "top-left without an origin",
			layout: []wm.OutputLayout{
				{Name: "DP-2", Enabled: true, X: 2560, Y: 0},
				{Name: "DP-1", Enabled: true, X: 1280, Y: 0},
			},
			want: "DP-1",
		},
		{
			name: "a disabled output at the origin is skipped",
			layout: []wm.OutputLayout{
				{Name: "DP-9", Enabled: false, X: 0, Y: 0},
				{Name: "eDP-1", Enabled: true, X: 0, Y: 0},
			},
			want: "eDP-1",
		},
		{
			name:   "nothing enabled publishes nothing",
			layout: []wm.OutputLayout{{Name: "DP-1", Enabled: false}},
			want:   "",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_ = os.Remove(file)
			publishGreeterPrimary(tc.layout)
			if got := read(); got != tc.want {
				t.Fatalf("published %q, want %q", got, tc.want)
			}
		})
	}
}

// TestResolutionPresets: a preset stores one monitor's mode and scale, the
// same bounds the picker's custom form enforces, under a name that cannot
// escape the presets dir. It never applies anything by itself.
func TestResolutionPresets(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	if err := savePreset("recording", "1280x720@60", "1.25"); err != nil {
		t.Fatalf("savePreset: %v", err)
	}
	raw, err := os.ReadFile(filepath.Join(presetsDir(), "recording.json"))
	if err != nil {
		t.Fatalf("preset not persisted: %v", err)
	}
	var p outputPreset
	if err := json.Unmarshal(raw, &p); err != nil {
		t.Fatalf("preset JSON: %v", err)
	}
	if p.Mode != "1280x720@60" || p.Scale != 1.25 {
		t.Fatalf("preset stored %+v", p)
	}

	for _, bad := range []struct{ label, name, mode, scale string }{
		{"escape", "../evil", "1280x720@60", "1"},
		{"tiny mode", "x", "320x100@60", "1"},
		{"slow mode", "x", "1280x720@10", "1"},
		{"scale out of range", "x", "1280x720@60", "4.5"},
		{"scale not a number", "x", "1280x720@60", "big"},
	} {
		if err := savePreset(bad.name, bad.mode, bad.scale); err == nil {
			t.Fatalf("savePreset(%q) accepted an invalid preset", bad.label)
		}
	}

	if err := rmPreset("recording"); err != nil {
		t.Fatalf("rmPreset: %v", err)
	}
	if _, err := os.Stat(filepath.Join(presetsDir(), "recording.json")); !os.IsNotExist(err) {
		t.Fatal("preset survived rm")
	}
	if err := rmPreset("recording"); err != nil {
		t.Fatalf("rmPreset of an absent preset should be quiet: %v", err)
	}
}
