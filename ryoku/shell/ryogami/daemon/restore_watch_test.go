package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	wm "ryoku-wm"
)

// restoreDaemon builds a daemon whose cache/config/state all point at temp
// dirs, so restoreOutputs runs against a controlled outputs.json without
// touching the real home.
func restoreDaemon(t *testing.T) (*daemon, string) {
	t.Helper()
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	if err := os.MkdirAll(cache, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(root, "state"))
	d := &daemon{surface: newWallSurface()}
	d.cfg.Paths.Cache = cache
	return d, cache
}

func TestRyogamiWatchKindsUsesOneUnionStream(t *testing.T) {
	for _, tc := range []struct {
		windows bool
		want    []wm.FrameKind
	}{
		{true, []wm.FrameKind{wm.FrameOutputs, wm.FrameWindows, wm.FrameWorkspaces, wm.FrameFocus, wm.FrameOverview}},
		{false, []wm.FrameKind{wm.FrameOutputs, wm.FrameWorkspaces, wm.FrameFocus, wm.FrameOverview}},
	} {
		if got := ryogamiWatchKinds(tc.windows); !reflect.DeepEqual(got, tc.want) {
			t.Fatalf("watch kinds (windows=%v) = %v, want %v", tc.windows, got, tc.want)
		}
	}
}

// The window list is streamed only for a rule that reads window geometry;
// process and overview rules never look at it.
func TestPauseNeedsWindowsOnlyForGeometryRules(t *testing.T) {
	for _, tc := range []struct {
		rules pauseRules
		want  bool
	}{
		{pauseRules{}, false},
		{pauseRules{processEnabled: true, overviewOnly: true, capOverviewState: true}, false},
		{pauseRules{fullWidth: true, capsKnown: true}, false},
		{pauseRules{fullWidth: true, capColumnFill: true, capsKnown: true}, true},
		{pauseRules{fullscreen: true}, true},
		{pauseRules{maximized: true}, true},
	} {
		if got := pauseNeedsWindows(tc.rules); got != tc.want {
			t.Fatalf("pauseNeedsWindows(%+v) = %v, want %v", tc.rules, got, tc.want)
		}
	}
}

// Until the caps probe answers, a full-width rule keeps the window list in the
// stream; once caps rule column fill out, it is dropped.
func TestStreamNeedsWindowsWhileCapsUnknown(t *testing.T) {
	for _, tc := range []struct {
		rules pauseRules
		want  bool
	}{
		{pauseRules{fullWidth: true}, true},
		{pauseRules{fullWidth: true, capsKnown: true}, false},
		{pauseRules{processEnabled: true}, false},
		{pauseRules{fullscreen: true, capsKnown: true}, true},
	} {
		if got := streamNeedsWindows(tc.rules); got != tc.want {
			t.Fatalf("streamNeedsWindows(%+v) = %v, want %v", tc.rules, got, tc.want)
		}
	}
}

// A stored static choice whose file is not present yet must be reported as
// unapplied (the login-race signal the startup retry keys on) and must never
// publish a bogus frame; once the file lands the same choice applies and the
// frame carries it. This is the regression: restoreOutputs used to give up on
// the missing file with no way for the caller to know it had to retry, leaving
// the desktop on the empty grey frame until a manual wallpaper set.
func TestRestoreRetriesUntilFilePresent(t *testing.T) {
	d, cache := restoreDaemon(t)
	pic := filepath.Join(t.TempDir(), "wall.png")
	if err := os.WriteFile(filepath.Join(cache, "outputs.json"),
		[]byte(`{"*":{"type":"static","path":"`+pic+`"}}`), 0o644); err != nil {
		t.Fatal(err)
	}

	if want, applied := d.restoreOutputs(); want != 1 || applied != 0 {
		t.Fatalf("missing file: want/applied = %d/%d, expected 1/0", want, applied)
	}
	if got := d.surface.snapshot().Default.Path; got != "" {
		t.Fatalf("a missing file must not publish a frame, got %q", got)
	}

	writeE2EPNG(t, pic)
	if want, applied := d.restoreOutputs(); want != 1 || applied != 1 {
		t.Fatalf("present file: want/applied = %d/%d, expected 1/1", want, applied)
	}
	if got := d.surface.snapshot().Default.Path; got != pic {
		t.Fatalf("restored frame path = %q, want %q", got, pic)
	}
}

// A recorded wallpaper that never arrives used to leave the session grey once
// the retry window closed: the daemon must then paint the default and record it.
func TestRestoreFallbackPaintsTheDefault(t *testing.T) {
	d, cache := restoreDaemon(t)
	walls := t.TempDir()
	d.cfg.Paths.Wallpaper = walls
	def := filepath.Join(walls, "fallback.png")
	writeE2EPNG(t, def)
	dead := filepath.Join(t.TempDir(), "gone.png")
	if err := os.WriteFile(filepath.Join(cache, "outputs.json"),
		[]byte(`{"*":{"type":"static","path":"`+dead+`"}}`), 0o644); err != nil {
		t.Fatal(err)
	}

	d.restoreFallback()

	if got := d.surface.snapshot().Default.Path; got != def {
		t.Fatalf("fallback frame = %q, want the default %q", got, def)
	}
	state := map[string]map[string]interface{}{}
	loadJSON(filepath.Join(cache, "outputs.json"), &state)
	if got, _ := state["*"]["path"].(string); got != def {
		t.Fatalf("recorded path = %q, want the fallback %q", got, def)
	}
}

// A choice that is merely late is untouched: the fallback paints it and leaves
// the recording alone.
func TestRestoreFallbackLeavesALiveChoice(t *testing.T) {
	d, cache := restoreDaemon(t)
	walls := t.TempDir()
	d.cfg.Paths.Wallpaper = walls
	writeE2EPNG(t, filepath.Join(walls, "fallback.png"))
	pic := filepath.Join(t.TempDir(), "chosen.png")
	writeE2EPNG(t, pic)
	if err := os.WriteFile(filepath.Join(cache, "outputs.json"),
		[]byte(`{"*":{"type":"static","path":"`+pic+`"}}`), 0o644); err != nil {
		t.Fatal(err)
	}

	d.restoreFallback()

	if got := d.surface.snapshot().Default.Path; got != pic {
		t.Fatalf("frame = %q, want the recorded choice %q", got, pic)
	}
	state := map[string]map[string]interface{}{}
	loadJSON(filepath.Join(cache, "outputs.json"), &state)
	if got, _ := state["*"]["path"].(string); got != pic {
		t.Fatalf("recorded path was rewritten to %q, want it left at %q", got, pic)
	}
}

// No stored choice is not a failure: want is zero, so the caller neither
// retries nor treats the empty frame as a login race (first run, restore off).
func TestRestoreNoChoiceIsNotPending(t *testing.T) {
	d, _ := restoreDaemon(t)
	if want, applied := d.restoreOutputs(); want != 0 || applied != 0 {
		t.Fatalf("no outputs.json: want/applied = %d/%d, expected 0/0", want, applied)
	}
}

// A box upgraded across the Ryogami split has the pre-split state file but an
// empty outputs.json; the daemon seeds outputs.json from it once so the
// wallpaper survives the upgrade, and never overwrites a choice already set
// through Ryogami.
func TestMigrateLegacyOutputs(t *testing.T) {
	d, cache := restoreDaemon(t)
	pic := filepath.Join(t.TempDir(), "old.png")
	writeE2EPNG(t, pic)
	state := filepath.Join(os.Getenv("XDG_STATE_HOME"))
	if err := os.MkdirAll(state, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(state, "ryoku-wallpaper.json"),
		[]byte(`{"default":"`+pic+`","outputs":{}}`), 0o644); err != nil {
		t.Fatal(err)
	}

	d.migrateLegacyOutputs()
	if want, applied := d.restoreOutputs(); want != 1 || applied != 1 {
		t.Fatalf("after migration: want/applied = %d/%d, expected 1/1", want, applied)
	}
	if got := d.surface.snapshot().Default.Path; got != pic {
		t.Fatalf("migrated wallpaper path = %q, want %q", got, pic)
	}

	// A real Ryogami choice already present is never clobbered by the seed.
	newer := filepath.Join(t.TempDir(), "new.png")
	writeE2EPNG(t, newer)
	if err := os.WriteFile(filepath.Join(cache, "outputs.json"),
		[]byte(`{"*":{"type":"static","path":"`+newer+`"}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	d.migrateLegacyOutputs()
	if want, applied := d.restoreOutputs(); want != 1 || applied != 1 {
		t.Fatalf("post-clobber-guard: want/applied = %d/%d, expected 1/1", want, applied)
	}
	if got := d.surface.snapshot().Default.Path; got != newer {
		t.Fatalf("migration overwrote a live choice: path = %q, want %q", got, newer)
	}
}

// defaultWallpaper is the startup fallback for a box with no recorded choice: it
// returns the first static image in the wallpaper dir by name, skipping
// subdirs, dotfiles, videos, and animated formats (a .gif is typeOf "video"),
// so the fallback never lands on the live player. An empty or missing dir
// yields "" (nothing to paint) rather than an error.
func TestDefaultWallpaperPicksFirstStatic(t *testing.T) {
	d, _ := restoreDaemon(t)
	wallDir := filepath.Join(t.TempDir(), "Wallpapers")
	d.cfg.Paths.Wallpaper = wallDir

	if got := d.defaultWallpaper(); got != "" {
		t.Fatalf("missing wallpaper dir must yield \"\", got %q", got)
	}
	if err := os.MkdirAll(filepath.Join(wallDir, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	if got := d.defaultWallpaper(); got != "" {
		t.Fatalf("dir with no images must yield \"\", got %q", got)
	}

	// Names that sort before the first real image, but must all be skipped: a
	// subdir, a dotfile, a clip, and an animated gif.
	for _, name := range []string{"0-clip.mp4", "1-anim.gif", ".hidden.png", "aardvark.jpg", "zebra.png"} {
		if err := os.WriteFile(filepath.Join(wallDir, name), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(wallDir, "sub", "0-nested.png"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got, want := d.defaultWallpaper(), filepath.Join(wallDir, "aardvark.jpg"); got != want {
		t.Fatalf("defaultWallpaper() = %q, want the first static image %q", got, want)
	}
}

// A box that never recorded a wallpaper (a fresh install, or one cut over from
// awww) must land on the shipped default instead of the empty grey frame:
// applyDefaultWallpaper paints the frame AND persists the choice to
// outputs.json, so the next login's restore reproduces it. This is the #149
// regression: the desktop went black because ryogami painted nothing when no
// choice was stored.
func TestApplyDefaultWallpaperPaintsAndPersists(t *testing.T) {
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	if err := os.MkdirAll(cache, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(root, "state"))
	wallDir := filepath.Join(root, "Wallpapers")
	pic := filepath.Join(wallDir, "default.png")
	writeE2EPNG(t, pic)

	d := &daemon{surface: newWallSurface(), store: openStore(cache), events: newEventHub(), video: newVideoPlayer(), lastTransition: -1}
	d.cfg.Paths.Cache = cache
	d.cfg.Paths.Wallpaper = wallDir

	d.applyDefaultWallpaper()

	if got := d.surface.snapshot().Default.Path; got != pic {
		t.Fatalf("default wallpaper frame path = %q, want %q", got, pic)
	}
	// Persisted, so a plain restore (no fallback) reproduces the choice next login.
	if want, applied := d.restoreOutputs(); want != 1 || applied != 1 {
		t.Fatalf("after default apply: restore want/applied = %d/%d, expected 1/1", want, applied)
	}
}
