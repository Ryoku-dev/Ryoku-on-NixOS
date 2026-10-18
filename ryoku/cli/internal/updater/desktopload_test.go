package updater

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func surfacesLog(t *testing.T) string {
	t.Helper()
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	dir := filepath.Join(state, "ryoku", "surfaces")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("lay out the surfaces directory: %v", err)
	}
	return filepath.Join(dir, "shell.log")
}

func limitDesktopLoadWait(t *testing.T, wait time.Duration) {
	t.Helper()
	old := desktopLoadWait
	t.Cleanup(func() { desktopLoadWait = old })
	desktopLoadWait = wait
}

func TestAFinishedLoadIsSeenAtOnce(t *testing.T) {
	path := surfacesLog(t)
	started := time.Now()
	if err := os.WriteFile(path, []byte("INFO: Launching config\nINFO: Configuration Loaded\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	limitDesktopLoadWait(t, 2*time.Second)
	began := time.Now()
	if !waitForDesktopLoaded(started) {
		t.Fatal("a log that reports a finished load was not accepted")
	}
	if waited := time.Since(began); waited > time.Second {
		t.Errorf("waited %v for a marker that was already there", waited)
	}
}

func TestACrashLoopIsNotAFinishedLoad(t *testing.T) {
	path := surfacesLog(t)
	started := time.Now()
	// What the daemon leaves behind between respawns: the attempt announced
	// itself and then died on the tree it was parsing.
	if err := os.WriteFile(path, []byte(`INFO: Launching config: "/home/u/.config/quickshell/shell/shell.qml"
ERROR: caused by @shell.qml[13:1]: module "shell.services" is not installed
`), 0o644); err != nil {
		t.Fatal(err)
	}
	limitDesktopLoadWait(t, 300*time.Millisecond)
	if waitForDesktopLoaded(started) {
		t.Fatal("a log of a failed load was reported as a loaded desktop")
	}
}

func TestNoLogAtAllIsNotAFinishedLoad(t *testing.T) {
	surfacesLog(t)
	limitDesktopLoadWait(t, 300*time.Millisecond)
	if waitForDesktopLoaded(time.Now()) {
		t.Fatal("a missing log was reported as a loaded desktop")
	}
}

func TestTheWaitKeepsLookingUntilTheDesktopLoads(t *testing.T) {
	path := surfacesLog(t)
	started := time.Now()
	if err := os.WriteFile(path, []byte("INFO: Launching config\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	limitDesktopLoadWait(t, 5*time.Second)
	go func() {
		time.Sleep(700 * time.Millisecond)
		// The daemon recreates the file on every attempt; this is the one that
		// gets through.
		_ = os.WriteFile(path, []byte("INFO: Launching config\nINFO: Configuration Loaded\n"), 0o644)
	}()
	began := time.Now()
	if !waitForDesktopLoaded(started) {
		t.Fatal("a desktop that loaded on a later attempt was never noticed")
	}
	if waited := time.Since(began); waited < 500*time.Millisecond {
		t.Errorf("returned after %v, before the load it claims to have seen", waited)
	}
}

func TestAStaleFinishedLoadDoesNotSatisfyTheWait(t *testing.T) {
	path := surfacesLog(t)
	if err := os.WriteFile(path, []byte("INFO: Configuration Loaded\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	stale := time.Now().Add(-time.Minute)
	if err := os.Chtimes(path, stale, stale); err != nil {
		t.Fatal(err)
	}
	started := time.Now()
	limitDesktopLoadWait(t, 300*time.Millisecond)
	if waitForDesktopLoaded(started) {
		t.Fatal("a finished-load line from the previous shell run was accepted")
	}
}
