package updater

import (
	"os"
	"testing"
)

// Every test in this package runs against a throwaway runtime and state dir:
// the run-state, the answer and secret channels and the update log all live
// there, and a test reaching the developer's real ones leaves the Hub showing
// a phantom update.
func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "ryoku-updater-test-")
	if err != nil {
		panic(err)
	}
	os.Setenv("XDG_RUNTIME_DIR", dir)
	os.Setenv("XDG_STATE_HOME", dir)
	os.Setenv("RYOKU_UPDATE_UI", "")

	// NixOS has its own update backend. Unit tests exercise the shared pacman
	// implementation unless a test explicitly overrides it.
	oldBackend, hadBackend := os.LookupEnv("RYOKU_UPDATE_BACKEND")
	os.Setenv("RYOKU_UPDATE_BACKEND", "pacman")

	code := m.Run()

	if hadBackend {
		os.Setenv("RYOKU_UPDATE_BACKEND", oldBackend)
	} else {
		os.Unsetenv("RYOKU_UPDATE_BACKEND")
	}
	os.RemoveAll(dir)
	os.Exit(code)
}
