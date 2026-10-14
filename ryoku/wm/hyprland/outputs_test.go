package main

import (
	"testing"

	wm "ryoku-wm"
)

// The neutral layout maps onto the spec ryoku-monitor reads, and an auto mode or
// scale must become preferred/1 rather than the empty string or 0 the script
// rejects, a bool VRR must become ryoku-monitor's 0/1, and disabled is the
// inverse of enabled. A mistake here hands ryoku-monitor a spec it cannot apply.
func TestLayoutToSpecs(t *testing.T) {
	specs := layoutToSpecs([]wm.OutputLayout{
		{Name: "eDP-1", Enabled: true, Mode: "2560x1600@165", Scale: 1.5, X: 0, Y: 0, Transform: 1, VRR: true, Mirror: "DP-1", ColorMode: "hdr", SdrBrightness: 1.5},
		{Name: "DP-1", Enabled: true},                // auto everything
		{Name: "HDMI-A-1", Enabled: false, Scale: 2}, // disabled
		{Name: ""}, // nameless: dropped
	})
	if len(specs) != 3 {
		t.Fatalf("got %d specs, want 3 (the nameless one is dropped)", len(specs))
	}
	if got := specs[0]; got.Mode != "2560x1600@165" || got.Scale != 1.5 || got.Position != "0x0" ||
		got.Transform != 1 || got.VRR != 1 || got.Disabled ||
		got.Mirror != "DP-1" || got.Cm != "hdr" || got.SdrBrightness != 1.5 {
		t.Errorf("eDP-1 spec = %+v", got)
	}
	if got := specs[1]; got.Mode != "preferred" || got.Scale != 1 || got.VRR != 0 || got.SdrBrightness != 1 {
		t.Errorf("an auto output must default to preferred/1/0 and 1x SDR, got %+v", got)
	}
	if got := specs[2]; !got.Disabled {
		t.Errorf("a disabled output must set disabled, got %+v", got)
	}
}
