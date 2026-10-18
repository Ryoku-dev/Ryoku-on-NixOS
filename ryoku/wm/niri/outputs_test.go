package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	wm "ryoku-wm"
)

// monitorsKdl is the write half of the display seam, and niri rejects the whole
// config on a bad node, taking the session down with it. So the rendered block is
// pinned by shape and validated by the real niri: an enabled output carries
// mode/scale/position and only the transform and VRR nodes it needs, a disabled
// one is a bare `off`.
func TestMonitorsKdl(t *testing.T) {
	got := string(monitorsKdl([]wm.OutputLayout{
		{Name: "eDP-1", Enabled: true, Mode: "2560x1600@165.002", Scale: 1.5, X: 0, Y: 0, Transform: 1, VRR: true},
		{Name: "DP-2", Enabled: false},
	}))

	for _, want := range []string{
		`output "eDP-1" {`,
		`mode "2560x1600@165.002"`,
		`scale 1.5`,
		`position x=0 y=0`,
		`transform "90"`,
		`variable-refresh-rate`,
		`output "DP-2" {`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("monitors.kdl missing %q\n%s", want, got)
		}
	}

	dp2 := got[strings.Index(got, `output "DP-2"`):]
	if !strings.Contains(dp2, "off") {
		t.Errorf("a disabled output must be `off`:\n%s", dp2)
	}
	if strings.Contains(dp2, "scale") || strings.Contains(dp2, "mode") {
		t.Errorf("a disabled output must carry no mode or scale:\n%s", dp2)
	}

	dir := niriHome(t)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "monitors.kdl"), []byte(got), 0o644); err != nil {
		t.Fatal(err)
	}
	validateGen(t, dir, "monitors.kdl")
}

// An untransformed, non-VRR output emits neither node, so the block stays minimal
// and a 0 transform never reads back as a rotation.
func TestMonitorsKdlOmitsDefaults(t *testing.T) {
	got := string(monitorsKdl([]wm.OutputLayout{
		{Name: "eDP-1", Enabled: true, Mode: "1920x1080@60", Scale: 1, X: 0, Y: 0},
	}))
	if strings.Contains(got, "transform") {
		t.Errorf("transform 0 must be omitted:\n%s", got)
	}
	if strings.Contains(got, "variable-refresh-rate") {
		t.Errorf("VRR off must be omitted:\n%s", got)
	}
}

func TestFallbackOutputKeepsOneConnectedDisplayOn(t *testing.T) {
	tests := []struct {
		name    string
		outputs []wm.Output
		want    string
	}{
		{
			name: "enabled external keeps panel off",
			outputs: []wm.Output{
				{Name: "DP-1"},
				{Name: "eDP-1", Disabled: true},
			},
		},
		{
			name: "internal panel wins after undock",
			outputs: []wm.Output{
				{Name: "DP-1", Disabled: true},
				{Name: "eDP-1", Disabled: true},
			},
			want: "eDP-1",
		},
		{
			name:    "external is still a safe fallback",
			outputs: []wm.Output{{Name: "DP-1", Disabled: true}},
			want:    "DP-1",
		},
		{name: "no connected outputs"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := fallbackOutput(tc.outputs); got != tc.want {
				t.Fatalf("fallbackOutput() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestReconcileOutputFallbackReturnsToPanelOffPreference(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	var got []string
	restore := stubRequest(t, func(req any) (json.RawMessage, error) {
		body, err := json.Marshal(req)
		got = append(got, string(body))
		return nil, err
	})
	defer restore()

	if reconcileOutputFallback([]wm.Output{
		{Name: "DP-1"},
		{Name: "eDP-1", Disabled: true},
	}) {
		t.Fatal("an enabled external output must not trigger a fallback")
	}
	if !reconcileOutputFallback([]wm.Output{
		{Name: "eDP-1", Disabled: true},
	}) {
		t.Fatal("all-disabled connected outputs did not trigger the fallback")
	}
	if marker := readOutputFallbackMarker(); marker != "eDP-1" {
		t.Fatalf("fallback marker = %q, want eDP-1", marker)
	}
	if !reconcileOutputFallback([]wm.Output{
		{Name: "DP-1"},
		{Name: "eDP-1"},
	}) {
		t.Fatal("the returning external output did not restore the panel-off preference")
	}
	if marker := readOutputFallbackMarker(); marker != "" {
		t.Fatalf("fallback marker survived restoration: %q", marker)
	}
	want := []string{
		`{"Output":{"action":"On","output":"eDP-1"}}`,
		`{"Output":{"action":"Off","output":"eDP-1"}}`,
	}
	if strings.Join(got, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("fallback requests\n got: %q\nwant: %q", got, want)
	}
}

// A profile saved on another compositor can carry mirror and HDR; replayed on
// niri, each is reported per leaf so the apply names its losses instead of
// failing or dropping them silently, while a neutral output reports nothing.
func TestOutputsUnhonoredReportsMirrorAndColour(t *testing.T) {
	unh := outputsUnhonored([]wm.OutputLayout{
		{Name: "eDP-1", Enabled: true, Mirror: "DP-1", ColorMode: "hdr", SdrBrightness: 1.5},
		{Name: "DP-1", Enabled: true, ColorMode: "srgb", SdrBrightness: 1},
	})
	got := map[string]bool{}
	for _, u := range unh {
		got[u.Key] = true
	}
	for _, want := range []string{"displays.eDP-1.mirror", "displays.eDP-1.colorMode", "displays.eDP-1.sdrBrightness"} {
		if !got[want] {
			t.Errorf("missing unhonored %q; got %v", want, unh)
		}
	}
	if got["displays.DP-1.mirror"] || got["displays.DP-1.colorMode"] || got["displays.DP-1.sdrBrightness"] {
		t.Errorf("a neutral output must report nothing; got %v", unh)
	}
}
