package main

import (
	"strings"
	"testing"

	wm "ryoku-wm"
)

// genBinds is the single total keybind set. These tests pin the two promises
// the switch and the cheatsheet depend on: every catalogue row is either
// emitted or explicitly reported (never silently missing), and every emitted
// chord has exactly one winner — mango silently keeps the last duplicate, so
// the generator must resolve every collision itself.

// emittedChords parses rebinds.conf into one winner check: the chord half of
// every bind line, normalised, with a count.
func emittedChords(body string) map[string]int {
	chords := map[string]int{}
	for _, line := range strings.Split(body, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		verb, rest, ok := strings.Cut(line, "=")
		if !ok || !strings.HasPrefix(verb, "bind") && verb != "axisbind" && verb != "mousebind" {
			continue
		}
		fields := strings.Split(rest, ",")
		if len(fields) < 2 {
			continue
		}
		chords[wm.NormChord(fields[0]+" + "+fields[1])]++
	}
	return chords
}

// mbKind reads the emitted verb for a catalogue id from the mapping table.
func mbKind(defs map[string]mangoBind, id string) string {
	return defs[id].kind
}

func TestGenBindsCoversWholeCatalogue(t *testing.T) {
	s := defaultStore()
	defs := defaultBinds()
	body, unh := genBinds(s)

	reported := map[string]bool{}
	for _, u := range unh {
		if strings.HasPrefix(u.Key, "bind.") {
			reported[strings.TrimSuffix(strings.TrimPrefix(u.Key, "bind."), ".10")] = true
		}
	}
	for _, cb := range wm.ShippedBinds() {
		if reported[cb.ID] {
			continue // named as unhonored, which is honest
		}
		// A row neither reported nor emitted would be a silent gap. Probe the
		// emitted chords through the row's own default chord: every bound row
		// must place its (possibly rebound) chord in the file.
		if cb.Family {
			// Families emit nine chords (1-9); check one.
			first := wm.ExpandChord(cb.Chord, 1)
			mods, key, _ := toMangoParts(first)
			want := wm.NormChord(mods + " + " + key)
			if _, ok := emittedChords(body)[want]; !ok {
				t.Errorf("family %q emitted no member for %q", cb.ID, first)
			}
			continue
		}
		_, mods, wantKey, ok := toMangoChord(cb.Chord, mbKind(defs, cb.ID))
		if !ok {
			t.Errorf("row %q has a chord the parser cannot read", cb.ID)
			continue
		}
		want := wm.NormChord(mods + " + " + wantKey)
		if _, ok := emittedChords(body)[want]; !ok {
			t.Errorf("catalogue row %q is neither emitted (%s) nor reported", cb.ID, want)
		}
	}

	// The tenth chord of every family: skipped, once per family, reported.
	ten := 0
	for _, u := range unh {
		if strings.HasSuffix(u.Key, ".10") {
			ten++
		}
	}
	if ten != 6 {
		t.Errorf("want six tenth-chord reports (three digit families on main and numpad keys), got %d", ten)
	}
}

// A rebind replaces the default, an unbind removes it, and a custom bind on a
// shipped chord wins over both.
func TestGenBindsResolvesEveryChordOnce(t *testing.T) {
	s := defaultStore()
	s.KeybindRebinds = map[string]string{"SUPER + Q": "SUPER + BACKSPACE"}
	s.Unbinds = []string{"SUPER + E"}
	s.Keybinds = []Keybind{{Keys: "SUPER + W", Action: "exec", Value: "echo hi"}}
	body, _ := genBinds(s)

	for chord, n := range emittedChords(body) {
		if n > 1 {
			t.Errorf("chord %q emitted %d times", chord, n)
		}
	}

	if !strings.Contains(body, "bind=SUPER,space,spawn,ryoku-shell launcher") {
		t.Error("unchanged defaults must still be emitted")
	}
	if !strings.Contains(body, "bind=SUPER,w,spawn_shell,echo hi") {
		t.Errorf("custom bind must win its chord:\n%s", body)
	}
	if strings.Contains(body, "spawn,ryogami wallpaper ui") {
		t.Error("a custom bind must displace the shipped chord it collides with")
	}
	if strings.Contains(body, "bind=SUPER,q,") {
		t.Error("a rebound chord must not still carry the default")
	}
	if strings.Contains(body, "bind=SUPER,e,spawn,ryoku-app files") {
		t.Error("an unbound chord must be gone")
	}
	// The rebind landed where the user asked.
	if !strings.Contains(body, "bind=SUPER,BACKSPACE,spawn_shell,") {
		t.Errorf("rebound SUPER+Q did not land on BackSpace:\n%s", body)
	}
}

// A custom bind whose command overflows mango's 255-byte config line is
// reported, never emitted: a truncated line would run half a command.
func TestGenBindsReportsOverlongCustom(t *testing.T) {
	s := defaultStore()
	long := "sh -c 'echo " + strings.Repeat("x", 300) + "'"
	s.Keybinds = []Keybind{{Keys: "SUPER + J", Action: "exec", Value: long}}
	body, unh := genBinds(s)
	if strings.Contains(body, "sh -c") {
		t.Error("an overlong custom bind must not be emitted")
	}
	found := false
	for _, u := range unh {
		if u.Key == "bind.custom.SUPER + J" && strings.Contains(u.Reason, "255") {
			found = true
		}
	}
	if !found {
		t.Errorf("overlong custom bind must be reported with the line-cap reason, got %+v", unh)
	}
}

// binds (the verb) prints the whole legend: shipped rows resolved against the
// store, then the user's customs. The cheatsheet and Hub draw it verbatim.
func TestBindRowsLegend(t *testing.T) {
	s := defaultStore()
	s.KeybindRebinds = map[string]string{"SUPER + Q": "SUPER + BACKSPACE"}
	s.Keybinds = []Keybind{{Keys: "CTRL + ALT + T", Action: "exec", Value: "kitty"}}
	rows := bindRows(s)
	if len(rows) != len(wm.ShippedBinds())+1 {
		t.Fatalf("legend rows %d, want %d", len(rows), len(wm.ShippedBinds())+1)
	}
	for _, r := range rows {
		if r.ID == "window.close" {
			if r.Chord != "SUPER + BACKSPACE" {
				t.Errorf("close chord = %q, want the rebind", r.Chord)
			}
			if r.Default != "SUPER + Q" {
				t.Errorf("close default = %q, want the shipped chord for the recorder", r.Default)
			}
		}
		if r.Label == "" {
			t.Errorf("row %q has no label", r.ID)
		}
	}
	// A row mango cannot perform is listed WITH its reason, never dropped.
	var tabbed *wm.BindRow
	for i, r := range rows {
		switch r.ID {
		case "column.tabbed":
			tabbed = &rows[i]
		case "custom.CTRL + ALT + T":
			if r.Kind != wm.BindCustom || !strings.Contains(r.Label, "kitty") {
				t.Errorf("custom row wrong: %+v", r)
			}
		}
	}
	if tabbed == nil || tabbed.Unhonored == "" {
		t.Error("column.tabbed must appear and name why mango cannot do it")
	}
}
