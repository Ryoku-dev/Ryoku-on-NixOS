package main

import "testing"

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
