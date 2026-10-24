package main

import (
	"path/filepath"
	"testing"

	wm "ryoku-wm"
)

// TestOutputsStateNamesEachDisplay: a wallpaper applied to every display is
// reported under each real output name (the Displays page keys placement, lock
// and colours by that name), and an audio change aimed at one of them updates
// the shared entry that all of them play.
func TestOutputsStateNamesEachDisplay(t *testing.T) {
	cache := t.TempDir()
	d := &daemon{events: newEventHub(), store: openStore(cache), surface: newWallSurface()}
	d.cfg.Paths.Cache = cache
	saveJSON(filepath.Join(cache, "outputs.json"), map[string]map[string]interface{}{
		"*": {"type": "video", "path": "/walls/a.mp4", "mute": true, "volume": 40},
	})
	prev := outputs.list()
	t.Cleanup(func() { outputs.set(prev) })
	outputs.set([]wm.Output{{Name: "DP-1", Width: 2560, Height: 1440}, {Name: "HDMI-A-1", Width: 1920, Height: 1080}})

	got := d.outputsState()
	if _, leaked := got["*"]; leaked || len(got) != 2 {
		t.Fatalf("outputs = %v, want DP-1 and HDMI-A-1 only", got)
	}
	for _, name := range []string{"DP-1", "HDMI-A-1"} {
		e, ok := got[name].(map[string]interface{})
		if !ok || e["path"] != "/walls/a.mp4" {
			t.Fatalf("%s = %v, want the shared wallpaper", name, got[name])
		}
	}
	if e := got["DP-1"].(map[string]interface{}); e["logical_width"] != 2560 {
		t.Fatalf("DP-1 size = %v, want its own geometry", e["logical_width"])
	}

	unmute := false
	d.setAudio(&unmute, nil, []string{"DP-1"})
	for _, name := range []string{"DP-1", "HDMI-A-1"} {
		if e := d.outputsState()[name].(map[string]interface{}); e["mute"] != false {
			t.Fatalf("%s mute = %v after unmuting a shared wallpaper, want false", name, e["mute"])
		}
	}
}
