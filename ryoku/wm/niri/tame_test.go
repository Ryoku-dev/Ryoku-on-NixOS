package main

import (
	"testing"
	"time"

	wm "ryoku-wm"
)

// The correction has to fire on exactly one shape, in one window of time, once.
// These pin that envelope, because the failure modes are all silent: correcting
// a window the user maximised for themselves, undoing a fullscreen, or firing
// twice and leaving the window full-width instead of tiled.

var (
	tameOutput      = wm.Output{Name: "eDP-2", Width: 1706, Height: 1066}
	clientMaximized = [2]int{1707, 977}
	fullscreen      = [2]int{1707, 1067}
	normalTile      = [2]int{829, 945}
)

func newTestTamer(enabled bool, clock *time.Time) *tamer {
	return &tamer{
		enabled:  enabled,
		gaps:     16,
		struts:   Struts{},
		baseline: map[uint64]struct{}{},
		opened:   map[uint64]time.Time{},
		done:     map[uint64]struct{}{},
		now:      func() time.Time { return *clock },
		// open re-reads through load; the fields above cover the paths that never
		// reach an open (a pre-existing window), so both agree on the setting.
		load: func() (bool, int, Struts) { return enabled, 16, Struts{} },
	}
}

// A window that opens itself maximised is cleared once, and never again.
func TestTamerClearsFreshOpenMaximised(t *testing.T) {
	now := time.Unix(0, 0)
	tm := newTestTamer(true, &now)
	tm.open(1)

	now = now.Add(40 * time.Millisecond) // niri commits set_maximized promptly
	if !tm.wantsClear(tameOutput, 1, clientMaximized[0], clientMaximized[1]) {
		t.Fatal("a fresh open in the client-maximised footprint must be cleared")
	}
	tm.cleared(1)
	if tm.wantsClear(tameOutput, 1, clientMaximized[0], clientMaximized[1]) {
		t.Fatal("a window already cleared must not be cleared again")
	}
}

// A window the user maximises well after it opened is left alone: same geometry,
// but past the grace, so it reads as a deliberate choice.
func TestTamerLeavesLaterMaximise(t *testing.T) {
	now := time.Unix(0, 0)
	tm := newTestTamer(true, &now)
	tm.open(1)

	now = now.Add(openMaximizeGrace + time.Second)
	if tm.wantsClear(tameOutput, 1, clientMaximized[0], clientMaximized[1]) {
		t.Fatal("a maximise past the grace must be left alone")
	}
}

// A window already up when the watch connects is the user's, not an open.
func TestTamerLeavesPreexisting(t *testing.T) {
	now := time.Unix(0, 0)
	tm := newTestTamer(true, &now)
	tm.seen(1) // replayed before ready
	tm.open(1) // the post-ready sighting must not adopt it
	if tm.wantsClear(tameOutput, 1, clientMaximized[0], clientMaximized[1]) {
		t.Fatal("a window present at connect must never be cleared")
	}
}

// Fullscreen and an ordinary tile are both left alone even fresh: only the
// client-maximised footprint is the one to correct.
func TestTamerIgnoresOtherFootprints(t *testing.T) {
	now := time.Unix(0, 0)
	tm := newTestTamer(true, &now)
	tm.open(1)
	if tm.wantsClear(tameOutput, 1, fullscreen[0], fullscreen[1]) {
		t.Fatal("a true fullscreen must never be cleared")
	}
	if tm.wantsClear(tameOutput, 1, normalTile[0], normalTile[1]) {
		t.Fatal("an ordinary tile is not maximised and must be left alone")
	}
}

// With the setting off the correction does nothing, whatever the geometry.
func TestTamerDisabled(t *testing.T) {
	now := time.Unix(0, 0)
	tm := newTestTamer(false, &now)
	tm.open(1)
	if tm.wantsClear(tameOutput, 1, clientMaximized[0], clientMaximized[1]) {
		t.Fatal("a disabled tamer must never clear")
	}
}

// A closed window's slot is released, so a reused id starts clean.
func TestTamerForgetResets(t *testing.T) {
	now := time.Unix(0, 0)
	tm := newTestTamer(true, &now)
	tm.open(1)
	tm.cleared(1)
	tm.forget(1)
	tm.open(1) // same id, new window
	if !tm.wantsClear(tameOutput, 1, clientMaximized[0], clientMaximized[1]) {
		t.Fatal("a forgotten id must be correctable again")
	}
}
