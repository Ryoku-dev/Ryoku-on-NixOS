package main

import (
	"time"
)

const (
	paletteIdleGrace     = 60 * time.Second
	paletteReconcileWait = 5 * time.Minute
)

// idlewatch frees an idle palette (launcher, overview) after a grace
// of not being used. These palettes draw nothing while hidden yet hold a full
// Qt/jemalloc process, so freeing one reclaims ~a quarter gig of RSS until the
// next open, which respawns and shows it in a single cold start (setGate wakes
// the supervisor; ipcCall retries until the fresh instance answers). On by
// default: the shell ships cheap on RAM, so a palette gives up its resident
// process the moment it is idle; a user who wants instant opens opts out per
// palette. Every failure mode resolves to "keep the palette loaded".

// parkable reports whether a component is one of the idle-freeable palettes.
// All three are on-demand (not persistent): they start on their first keybind
// and park again after the idle grace.
func parkable(name string) bool {
	return name == "launcher" || name == "overview"
}

// unloadPaletteWhenIdle is the per-palette control that frees it after a grace
// of being hidden. On by default (perfFlagDefault true): the palette is on-
// demand, so keeping it after use only wastes RAM; a user opts OUT to keep it
// warm between opens. Keys live in performance.json beside the other unload
// flags.
func unloadPaletteWhenIdle(name string) bool {
	switch name {
	case "launcher":
		return perfFlagDefault("unloadLauncherWhenIdle", true)
	case "overview":
		return perfFlagDefault("unloadOverviewWhenIdle", true)
	}
	return false
}

// markHidden / markShown record a palette's visibility for the idle-park worker.
// The palette QML reports every open change over the `state` command; a fresh
// process is assumed hidden (both palettes boot hidden and supervise marks them
// so), which starts the grace at launch so a never-opened palette parks on its
// own.
func (d *daemon) kickPalettePark() {
	select {
	case d.parkSig <- struct{}{}:
	default:
	}
}

func (d *daemon) markHidden(name string) {
	d.parkMu.Lock()
	d.hiddenSince[name] = time.Now()
	d.parkMu.Unlock()
	d.kickPalettePark()
}

func (d *daemon) markShown(name string) {
	d.parkMu.Lock()
	delete(d.hiddenSince, name)
	d.parkMu.Unlock()
	d.kickPalettePark()
}

// setPaletteVisible is the `state <name> <0|1>` handler: visible cancels the park
// grace, hidden starts it.
func (d *daemon) setPaletteVisible(name string, visible bool) {
	if visible {
		d.markShown(name)
	} else {
		d.markHidden(name)
	}
}

// parkDue reports whether a palette hidden since `since` has been idle past the
// grace. Pure, so the worker's decision is unit-testable. A palette that is not
// currently hidden (absent from hiddenSince) is never due.
func parkDue(since time.Time, hidden bool, grace time.Duration, now time.Time) bool {
	return hidden && now.Sub(since) >= grace
}

func nextPaletteParkWait(hidden map[string]time.Time, eligible map[string]bool, grace time.Duration, now time.Time) time.Duration {
	wait := paletteReconcileWait
	for name, since := range hidden {
		if !eligible[name] {
			continue
		}
		left := grace - now.Sub(since)
		if left <= 0 {
			return 0
		}
		if left < wait {
			wait = left
		}
	}
	return wait
}

// idlePark sleeps until the next hidden palette is actually due. Visibility
// reports and power-profile changes rouse it; a slow reconciliation covers a
// hand-edited performance file without a ten-second permanent ticker.
func (d *daemon) idlePark() {
	timer := time.NewTimer(0)
	defer timer.Stop()
	for {
		now := time.Now()
		eligible := map[string]bool{}
		for _, name := range []string{"launcher", "overview"} {
			eligible[name] = unloadPaletteWhenIdle(name) || d.saverActive()
		}

		d.parkMu.Lock()
		hidden := make(map[string]time.Time, len(d.hiddenSince))
		for name, since := range d.hiddenSince {
			hidden[name] = since
		}
		d.parkMu.Unlock()

		for _, name := range []string{"launcher", "overview"} {
			since, isHidden := hidden[name]
			if !eligible[name] || !parkDue(since, isHidden, paletteIdleGrace, now) {
				continue
			}
			d.mu.Lock()
			running := d.proc[name] != nil
			d.mu.Unlock()
			if running {
				d.setGate(name, false)
			}
			d.parkMu.Lock()
			delete(d.hiddenSince, name)
			delete(hidden, name)
			d.parkMu.Unlock()
		}

		wait := nextPaletteParkWait(hidden, eligible, paletteIdleGrace, now)
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		timer.Reset(wait)
		select {
		case <-d.quit:
			return
		case <-d.parkSig:
		case <-timer.C:
		}
	}
}
