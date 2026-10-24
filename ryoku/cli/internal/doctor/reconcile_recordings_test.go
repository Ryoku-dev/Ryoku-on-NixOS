package doctor

import (
	"os"
	"path/filepath"
	"testing"
)

// recFixture builds an isolated HOME with nothing recorded yet, so each test
// controls exactly what exists before the reconciler runs.
func recFixture(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_VIDEOS_DIR", "")
	t.Setenv("RYOKU_SHELL_RECORDINGS_DIR", "")
	return home
}

// TestRecordingsCreatesMissingDir: check-only reports the missing directory
// without touching disk; apply creates it and a second pass is a no-op.
func TestRecordingsCreatesMissingDir(t *testing.T) {
	home := recFixture(t)
	dir := filepath.Join(home, "Videos", "Recordings")

	if got := reconcileRecordingsDir(true); got.status != recWouldFix {
		t.Fatalf("check-only should report a fix, got %v (%s)", got.status, got.detail)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatal("check-only must not create anything")
	}

	if got := reconcileRecordingsDir(false); got.status != recFixed {
		t.Fatalf("apply should fix, got %v (%s)", got.status, got.detail)
	}
	if _, err := os.Stat(dir); err != nil {
		t.Errorf("the recordings directory was not created: %v", err)
	}

	// Idempotent: a second pass has nothing left to do.
	if got := reconcileRecordingsDir(false); got.status != recOK {
		t.Errorf("second pass should be a no-op, got %v (%s)", got.status, got.detail)
	}
}

// TestRecordingsHonoursTheSetting: the Hub's `directory` key is what everything
// resolves, so the reconciler has to follow it too.
func TestRecordingsHonoursTheSetting(t *testing.T) {
	home := recFixture(t)
	custom := filepath.Join(home, "Clips")
	if err := os.MkdirAll(filepath.Join(home, ".config", "ryoku"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".config", "ryoku", "recording.json"),
		[]byte(`{"fps":60,"directory":"`+custom+`"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := recordingsDir(); got != custom {
		t.Fatalf("recordingsDir() = %q, want the configured %q", got, custom)
	}
	if got := reconcileRecordingsDir(false); got.status != recFixed {
		t.Fatalf("apply should create the configured directory, got %v (%s)", got.status, got.detail)
	}
	if _, err := os.Stat(custom); err != nil {
		t.Errorf("the configured directory was not created: %v", err)
	}
}

// TestRecordingsLeavesForeignSinkAlone: gpu-screen-recorder's own default is
// reported, never migrated, since someone may be running it deliberately.
func TestRecordingsLeavesForeignSinkAlone(t *testing.T) {
	home := recFixture(t)
	stray := filepath.Join(home, "Videos", "ScreenRecordings")
	if err := os.MkdirAll(stray, 0o755); err != nil {
		t.Fatal(err)
	}
	clip := filepath.Join(stray, "2026_07_26_14_26_17_record.mp4")
	if err := os.WriteFile(clip, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	got := reconcileRecordingsDir(false)
	if got.status != recNote {
		t.Fatalf("a foreign sink should be a note, got %v (%s)", got.status, got.detail)
	}
	if _, err := os.Stat(clip); err != nil {
		t.Error("the foreign recording must be left where it is")
	}
	if got.remedy == "" {
		t.Error("the note should carry the command to move them")
	}
}
