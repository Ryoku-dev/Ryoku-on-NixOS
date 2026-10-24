package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"

	wm "ryoku-wm"
)

// widgetwatch frees the desktop-widget layer's memory when windows cover the
// desktop on every monitor, if the user opted in. The widgets ride the wallpaper
// layer, so when no monitor shows an empty workspace they are already invisible;
// unloading the process then reclaims its scene-graph + GL memory until an empty
// desktop returns. Every failure mode resolves to "keep the widgets loaded", so
// a probe miss never leaves a bare desktop.

// parsePerfFlag reads a boolean opt-in from a performance.json body. Anything
// malformed, absent, or the wrong type is false, so an optimisation stays off
// unless the user clearly turned it on.
func parsePerfFlag(b []byte, key string) bool {
	var m map[string]any
	if json.Unmarshal(b, &m) != nil {
		return false
	}
	v, _ := m[key].(bool)
	return v
}

// ryokuConfigDir is ~/.config/ryoku (honouring XDG_CONFIG_HOME), the dir the
// Ryoku Settings sections write. Empty only when the home dir is unknowable.
func ryokuConfigDir() string {
	dir := os.Getenv("XDG_CONFIG_HOME")
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		dir = filepath.Join(home, ".config")
	}
	return filepath.Join(dir, "ryoku")
}

// perfPath is ~/.config/ryoku/performance.json, the file the Performance section
// in Ryoku Settings writes. Empty only when the home dir is unknowable.
func perfPath() string {
	dir := ryokuConfigDir()
	if dir == "" {
		return ""
	}
	return filepath.Join(dir, "performance.json")
}

// perfFlag reads one opt-in out of performance.json. A missing file is off.
func perfFlag(key string) bool {
	b, err := os.ReadFile(perfPath())
	if err != nil {
		return false
	}
	return parsePerfFlag(b, key)
}

// perfFlagDefault is perfFlag with an explicit default, for optimisations that
// ship on by default (the user opts out). A missing file, missing key, or wrong
// type all yield def.
func perfFlagDefault(key string, def bool) bool {
	b, err := os.ReadFile(perfPath())
	if err != nil {
		return def
	}
	var m map[string]any
	if json.Unmarshal(b, &m) != nil {
		return def
	}
	if v, ok := m[key].(bool); ok {
		return v
	}
	return def
}

// On by default: the widgets ride the wallpaper, so freeing them while every
// screen is covered is invisible and reclaims their scene-graph + GL memory.
func unloadWidgetsWhenCovered() bool { return perfFlagDefault("unloadWidgetsWhenCovered", true) }

// desktopVisibleFrom reports whether any output's active workspace holds no
// windows, i.e. the wallpaper (and the widgets on it) is showing. An empty
// output list, or an output on an unknown workspace, reads as visible, so the
// widgets are only parked on a confident, fully-covered reading.
func desktopVisibleFrom(outputs []wm.Output, workspaces []wm.Workspace) bool {
	if len(outputs) == 0 {
		return true
	}
	windows := make(map[string]int, len(workspaces))
	for _, w := range workspaces {
		windows[w.ID] = w.Windows
	}
	for _, o := range outputs {
		if windows[o.ActiveWorkspace] == 0 {
			return true
		}
	}
	return false
}

// desktopVisible reads coverage from the watcher cache. A cold cache reads as
// visible, keeping the widgets up.
func (d *daemon) desktopVisible() bool {
	d.wmMu.Lock()
	outputs := d.wmOutputs
	workspaces := d.wmWorkspaces
	d.wmMu.Unlock()
	return desktopVisibleFrom(outputs, workspaces)
}

// widgetGateWorker parks the widget layer after a grace period of being fully
// covered and reloads it on the next workspace/output event. Its timer is armed
// for the actual grace deadline; a slow reconciliation only covers hand-edited
// performance settings.
func (d *daemon) widgetGateWorker() {
	const (
		grace     = 3 * time.Second
		reconcile = 5 * time.Minute
	)
	var coveredSince time.Time
	reeval := func(now time.Time) time.Duration {
		if (!unloadWidgetsWhenCovered() && !d.saverActive()) || d.desktopVisible() {
			coveredSince = time.Time{}
			d.setGate("widgets", true)
			return reconcile
		}
		if coveredSince.IsZero() {
			coveredSince = now
		}
		if left := grace - now.Sub(coveredSince); left > 0 {
			return left
		}
		d.setGate("widgets", false)
		return reconcile
	}

	timer := time.NewTimer(0)
	defer timer.Stop()
	for {
		wait := reeval(time.Now())
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
		case <-d.widgetSig:
		case <-timer.C:
		}
	}
}
