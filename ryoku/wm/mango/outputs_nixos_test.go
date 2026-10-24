package main

import (
	"strings"
	"testing"

	wm "ryoku-wm"
)

func TestMonitorsConfTranslatesNegativeCanvasAsOneBlock(t *testing.T) {
	layout := []wm.OutputLayout{
		{
			Name:    "DP-1",
			Enabled: true,
			Mode:    "2560x1440@200",
			Scale:   1,
			X:       0,
			Y:       0,
		},
		{
			Name:    "DP-2",
			Enabled: true,
			Mode:    "1920x1080@60",
			Scale:   1,
			X:       272,
			Y:       -1080,
		},
	}

	got := string(monitorsConf(layout))

	for _, want := range []string{
		"name:^DP-1$,width:2560,height:1440,refresh:200,x:0,y:1080,scale:1",
		"name:^DP-2$,width:1920,height:1080,refresh:60,x:272,y:0,scale:1",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("generated layout lost relative placement\nwant: %s\n\ngot:\n%s", want, got)
		}
	}
}

func TestParseRandrKeepsRefreshPositionAndPhysicalWidth(t *testing.T) {
	raw := `DP-1 "Microstep MSI MP251 PC2M085601854"
  Physical size: 540x310 mm
  Enabled: yes
  Modes:
    2560x1440 px, 200.000000 Hz (current)
    2560x1440 px, 165.000000 Hz
  Position: 0,1080
  Transform: normal
  Scale: 1.000000
`

	got, ok := parseRandr(raw, "DP-1")

	if !ok {
		t.Fatal("output was not detected")
	}

	if got.mode != "2560x1440@200" {
		t.Fatalf("current mode = %q", got.mode)
	}

	if len(got.modes) != 2 ||
		got.modes[0] != "2560x1440@200" ||
		got.modes[1] != "2560x1440@165" {
		t.Fatalf("modes = %#v", got.modes)
	}

	if got.x != 0 || got.y != 1080 {
		t.Fatalf("position = %d,%d", got.x, got.y)
	}

	if got.physicalWidth != 540 {
		t.Fatalf("physical width = %d", got.physicalWidth)
	}

	if got.model != "Microstep MSI MP251 PC2M085601854" {
		t.Fatalf("model = %q", got.model)
	}
}
