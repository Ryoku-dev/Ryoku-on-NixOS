package main

import (
	"sync"
	"time"
)

// Taming the windows apps open maximised. mango honours a client's maximize
// request at map time by filling the working area edge to edge, gaps and all,
// which is not where the desktop wants a window to land (the same promise
// Hyprland's resize plugin and niri's tamer keep). mango offers no config
// refusal on 0.17.4 — the noopenmaximized rule its docs list is not in this
// parser — so the lever is the same as niri's: clear the state the moment it
// appears, riding the watch stream this provider already reads.
//
// Unlike niri, mango reports is_maximized directly, so the correction keys on
// the real flag rather than a geometry guess. The correction is confined to
// the open: only a window that arrives maximised within a short grace of
// mapping is reset, and only once. A window already up when the watch
// connects, a window the user maximises later with its own keybind, and true
// fullscreen are all left as they are.

// openMaximizeGrace is how long after a window maps its maximise still counts
// as part of the open. A client commits its maximize request within tens of
// milliseconds of the map, so a second is a wide margin over that and far
// below any deliberate maximise a person makes after settling in.
const openMaximizeGrace = time.Second

type tamer struct {
	mu        sync.Mutex
	started   map[int]time.Time // first sighting after ready
	done      map[int]struct{}  // windows already corrected or dismissed
	baseline  map[int]struct{}  // windows that existed before this watch
	enabledAt func() bool       // reads desktop.windows.tameMaximizeOnOpen
}

func newTamer() *tamer {
	return &tamer{
		started:   map[int]time.Time{},
		done:      map[int]struct{}{},
		baseline:  map[int]struct{}{},
		enabledAt: func() bool { return loadStore(storePath()).Windows.TameMaximizeOnOpen },
	}
}

// seen records a window replayed during the connect burst, before the session
// is ready. It existed before this watch did, so its state is the user's.
func (t *tamer) seen(id int) { t.baseline[id] = struct{}{} }

// open stamps the first sighting of a window after the session is ready.
func (t *tamer) open(id int) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if _, ok := t.started[id]; !ok {
		t.started[id] = time.Now()
	}
}

// wantsClear reports whether a window is an app that just opened itself
// maximised and should be reset: enabled, freshly opened, not already
// handled, carrying the live maximised flag, and not fullscreen (an app that
// opens fullscreen meant it).
func (t *tamer) wantsClear(c mangoClient) bool {
	if c.IsFullscreen || !c.IsMaximized {
		return false
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if !t.enabledAt() {
		return false
	}
	if _, ok := t.baseline[c.ID]; ok {
		return false
	}
	if _, ok := t.done[c.ID]; ok {
		return false
	}
	first, ok := t.started[c.ID]
	if !ok {
		return false
	}
	return time.Since(first) <= openMaximizeGrace
}

func (t *tamer) cleared(id int) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.done[id] = struct{}{}
	delete(t.started, id)
}

func (t *tamer) forget(id int) {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.started, id)
	delete(t.done, id)
	delete(t.baseline, id)
}

// clearMaximized resets a window an app opened maximised back to an ordinary
// tile. mango toggles per focused window, and a window that just mapped is the
// focused one anyway; targeting by id keeps it exact. Best effort: a failed
// dispatch just leaves the window as the app asked, the behaviour before this.
var clearMaximized = func(id int) {
	_ = dispatch("togglemaximizescreen", clientSuffix(id))
}
