package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	wm "ryoku-wm"
)

// At login the wallpaper file (a late mount) or the outputs (a late monitor)
// can lag the daemon; a one-shot restore then left the grey default for the
// session. retryRestore covers the first, watchWindowManager the second.

const (
	restoreRetryWindow   = 30 * time.Second
	restoreRetryInterval = 1 * time.Second
)

func (d *daemon) retryRestore() {
	deadline := time.Now().Add(restoreRetryWindow)
	for time.Now().Before(deadline) {
		time.Sleep(restoreRetryInterval)
		if want, applied := d.restoreOutputs(); want == 0 || applied > 0 {
			return
		}
	}
	// The window covers a late mount or a finishing download; a choice still
	// missing after it is a dead path, and grey for the session is worse than
	// the default.
	d.restoreFallback()
}

// restoreFallback repaints the stored outputs against the default wallpaper and
// records it, so a dead choice heals at login instead of greying every time.
func (d *daemon) restoreFallback() {
	if want, applied := d.restoreOutputs(); want == 0 || applied > 0 {
		return // it landed as the window closed, or nothing was ever recorded
	}
	src := d.defaultWallpaper()
	if src == "" {
		return // nothing installed to fall back to
	}
	path := filepath.Join(d.config().cacheDir(), "outputs.json")
	state := map[string]map[string]interface{}{}
	loadJSON(path, &state)
	if len(state) == 0 {
		return
	}
	for _, e := range state {
		e["path"] = src
	}
	saveJSON(path, state)
	if _, applied := d.restoreOutputs(); applied > 0 {
		fmt.Fprintf(os.Stderr, "ryogami: recorded wallpaper never arrived; painted %s\n",
			filepath.Base(src))
	}
}

// The window list is the costliest kind to keep current: every title change and
// move refreshes it. Only the geometry pause rules read it, so the stream
// carries it only while one of them is on.
func ryogamiWatchKinds(windows bool) []wm.FrameKind {
	kinds := []wm.FrameKind{wm.FrameOutputs}
	if windows {
		kinds = append(kinds, wm.FrameWindows)
	}
	return append(kinds, wm.FrameWorkspaces, wm.FrameFocus, wm.FrameOverview)
}

// streamNeedsWindows reads unknown caps as possible column fill: a full-width
// rule whose caps probe failed at stream start keeps the list instead of going
// blind until the next settings change or reconnect.
func streamNeedsWindows(r pauseRules) bool {
	return pauseNeedsWindows(r) || (r.fullWidth && !r.capsKnown)
}

var wmWatch struct {
	mu      sync.Mutex
	windows bool
	cancel  context.CancelFunc
}

// watchWindowManager owns Ryogami's single provider stream. Every frame is
// fanned through the output restore/cache and playback/workspace consumers in
// provider order; reconnecting keeps the same fixed backoff used by the former
// window-state watcher. A stream cancelled by rewatchForPauseRules restarts at
// once with the new kinds.
func (d *daemon) watchWindowManager() {
	for {
		ctx, cancel := context.WithCancel(context.Background())
		wmWatch.mu.Lock()
		windows := streamNeedsWindows(d.currentPauseRules())
		wmWatch.windows, wmWatch.cancel = windows, cancel
		wmWatch.mu.Unlock()
		if !windows {
			wmCache.mu.Lock()
			wmCache.windows = nil
			wmCache.mu.Unlock()
		}

		var previousOutputs map[string]bool
		_ = wmClient.WatchKinds(ctx, ryogamiWatchKinds(windows), func(f wm.Frame) {
			if f.Kind == wm.FrameOutputs {
				d.handleOutputFrame(f.Outputs, &previousOutputs)
			}
			d.handleWindowStateFrame(f)
		})
		rewatch := ctx.Err() != nil
		cancel()
		if !rewatch {
			time.Sleep(500 * time.Millisecond)
		}
	}
}

func (d *daemon) rewatchForPauseRules() {
	wmWatch.mu.Lock()
	defer wmWatch.mu.Unlock()
	if wmWatch.cancel != nil && wmWatch.windows != streamNeedsWindows(d.currentPauseRules()) {
		wmWatch.cancel()
	}
}

func init() {
	watchSetting("playback.", func(d *daemon, _ string, _ interface{}) { d.rewatchForPauseRules() })
}

func (d *daemon) handleOutputFrame(frame []wm.Output, previous *map[string]bool) {
	outputs.set(frame)
	current := map[string]bool{}
	for _, output := range frame {
		current[output.Name] = true
	}
	if *previous != nil && d.config().restoreEnabled() {
		var added []string
		for name := range current {
			if !(*previous)[name] {
				added = append(added, name)
			}
		}
		if len(added) > 0 {
			d.restoreOutputTargets(added)
			for _, name := range added {
				if target, err := d.workspaces.current(name); err == nil {
					_ = d.applyWorkspaceTarget(target, "init")
				}
			}
		}
	}
	*previous = current
}
