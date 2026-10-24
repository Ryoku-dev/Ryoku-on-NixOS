package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestParkable(t *testing.T) {
	for _, n := range []string{"launcher", "overview"} {
		if !parkable(n) {
			t.Errorf("%s should be parkable", n)
		}
	}
	for _, n := range []string{"shell", "visualizer", "widgets", "hub", ""} {
		if parkable(n) {
			t.Errorf("%s should not be parkable", n)
		}
	}
}

func TestParkDue(t *testing.T) {
	now := time.Now()
	grace := 60 * time.Second
	cases := []struct {
		name   string
		since  time.Time
		hidden bool
		want   bool
	}{
		{"not hidden", now, false, false},
		{"hidden under grace", now.Add(-30 * time.Second), true, false},
		{"hidden at grace", now.Add(-grace), true, true},
		{"hidden past grace", now.Add(-90 * time.Second), true, true},
	}
	for _, c := range cases {
		if got := parkDue(c.since, c.hidden, grace, now); got != c.want {
			t.Errorf("%s: parkDue = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestNextPaletteParkWait(t *testing.T) {
	now := time.Unix(1000, 0)
	grace := 60 * time.Second
	cases := []struct {
		name     string
		hidden   map[string]time.Time
		eligible map[string]bool
		want     time.Duration
	}{
		{"nothing hidden reconciles slowly", nil, nil, paletteReconcileWait},
		{"ineligible hidden palette is ignored", map[string]time.Time{"launcher": now.Add(-time.Hour)}, nil, paletteReconcileWait},
		{"next deadline is exact", map[string]time.Time{"launcher": now.Add(-20 * time.Second)}, map[string]bool{"launcher": true}, 40 * time.Second},
		{"overdue returns immediately", map[string]time.Time{"overview": now.Add(-grace)}, map[string]bool{"overview": true}, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := nextPaletteParkWait(tc.hidden, tc.eligible, grace, now); got != tc.want {
				t.Fatalf("nextPaletteParkWait = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestSetPaletteVisible(t *testing.T) {
	d := &daemon{hiddenSince: map[string]time.Time{}}

	d.setPaletteVisible("launcher", false) // hidden -> grace starts
	d.parkMu.Lock()
	_, hidden := d.hiddenSince["launcher"]
	d.parkMu.Unlock()
	if !hidden {
		t.Fatal("a hidden report must record hiddenSince")
	}

	d.setPaletteVisible("launcher", true) // shown -> grace cancelled
	d.parkMu.Lock()
	_, stillHidden := d.hiddenSince["launcher"]
	d.parkMu.Unlock()
	if stillHidden {
		t.Fatal("a shown report must clear hiddenSince")
	}
}

func TestUnloadPaletteWhenIdle(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	if err := os.MkdirAll(filepath.Join(dir, "ryoku"), 0o755); err != nil {
		t.Fatal(err)
	}
	// launcher opts OUT explicitly; overview is unset.
	if err := os.WriteFile(filepath.Join(dir, "ryoku", "performance.json"),
		[]byte(`{"unloadLauncherWhenIdle":false}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if unloadPaletteWhenIdle("launcher") {
		t.Error("launcher explicitly false -> off")
	}
	if !unloadPaletteWhenIdle("overview") {
		t.Error("overview unset -> on by default (cheap default)")
	}
	if unloadPaletteWhenIdle("shell") {
		t.Error("shell is not a parkable palette")
	}
}

func TestStartsAtBoot(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	if err := os.MkdirAll(filepath.Join(dir, "ryoku"), 0o755); err != nil {
		t.Fatal(err)
	}
	if !startsAtBoot(component{"shell", true}) {
		t.Error("a persistent component starts at boot")
	}
	if startsAtBoot(component{"launcher", false}) {
		t.Error("an on-demand palette does not start at boot")
	}
	_ = os.WriteFile(filepath.Join(dir, "ryoku", "performance.json"),
		[]byte(`{"disabledComponents":["launcher"]}`), 0o644)
	if startsAtBoot(component{"launcher", true}) {
		t.Error("a disabled component never starts at boot")
	}
}
