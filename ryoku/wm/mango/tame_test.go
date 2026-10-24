package main

import (
	"testing"
	"time"

	wm "ryoku-wm"
)

// The open-maximise correction rides the windows fold: only a window that
// arrives maximised within the grace of mapping is reset, once, and only
// while the store switch is on.

func maxClient(id int) mangoClient {
	c := client(id, true, 1)
	c.IsMaximized = true
	return c
}

func TestTamerClearsOnlyFreshOpens(t *testing.T) {
	tr := &tamer{
		started:   map[int]time.Time{},
		done:      map[int]struct{}{},
		baseline:  map[int]struct{}{},
		enabledAt: func() bool { return true },
	}
	// A window that existed before the watch: baseline, never touched.
	tr.seen(1)
	if tr.wantsClear(maxClient(1)) {
		t.Error("a pre-existing maximised window must be left alone")
	}
	// A fresh open, inside the grace: clear once.
	tr.open(2)
	if !tr.wantsClear(maxClient(2)) {
		t.Error("a window that opened maximised must be cleared")
	}
	tr.cleared(2)
	if tr.wantsClear(maxClient(2)) {
		t.Error("a window already corrected must not be corrected twice")
	}
	// A fresh open past the grace (the user maximised it later): left alone.
	tr.open(3)
	tr.started[3] = time.Now().Add(-2 * openMaximizeGrace)
	if tr.wantsClear(maxClient(3)) {
		t.Error("a deliberate later maximise must be left alone")
	}
	// Fullscreen means the app meant it.
	full := maxClient(4)
	full.IsFullscreen = true
	tr.open(4)
	if tr.wantsClear(full) {
		t.Error("a fullscreen open must be left alone")
	}
	// Not maximised: nothing to clear.
	plain := client(5, true, 1)
	tr.open(5)
	if tr.wantsClear(plain) {
		t.Error("an ordinary tile must not be cleared")
	}
	// The store switch off: nothing clears.
	tr.enabledAt = func() bool { return false }
	tr.open(6)
	if tr.wantsClear(maxClient(6)) {
		t.Error("a disabled tamer must never clear")
	}
}

// trackOpen is the fold seam: before ready every window is baseline, after
// ready a new id is stamped as an open, and a closed id leaves the tamer so a
// recycled id starts clean.
func TestTrackOpenLifecycle(t *testing.T) {
	s, _ := newTestSession(wm.FrameWindows)
	s.tamer = &tamer{
		started:   map[int]time.Time{},
		done:      map[int]struct{}{},
		baseline:  map[int]struct{}{},
		enabledAt: func() bool { return true },
	}
	// Not ready yet: the connect burst is all baseline.
	s.fold(rawLine{kind: wm.FrameWindows, line: clientsLine(t, maxClient(1))})
	if _, ok := s.tamer.baseline[1]; !ok {
		t.Fatal("a window seen before ready must be baseline")
	}
	s.ready = true
	// A fresh maximised window after ready is corrected in the same push:
	// stamped, cleared, and the reset dispatched once.
	cleared := 0
	old := clearMaximized
	clearMaximized = func(int) { cleared++ }
	defer func() { clearMaximized = old }()
	s.fold(rawLine{kind: wm.FrameWindows, line: clientsLine(t, maxClient(1), maxClient(2))})
	if cleared != 1 {
		t.Fatalf("clearMaximized fired %d times, want 1 (once, for the fresh open only)", cleared)
	}
	s.tamer.mu.Lock()
	_, done := s.tamer.done[2]
	s.tamer.mu.Unlock()
	if !done {
		t.Error("the corrected window must be marked done")
	}
	// It closes: it leaves the tamer entirely, so a recycled id starts clean.
	s.fold(rawLine{kind: wm.FrameWindows, line: clientsLine(t, maxClient(1))})
	s.tamer.mu.Lock()
	_, still := s.tamer.done[2]
	s.tamer.mu.Unlock()
	if still {
		t.Error("a closed window must leave the tamer")
	}
}
