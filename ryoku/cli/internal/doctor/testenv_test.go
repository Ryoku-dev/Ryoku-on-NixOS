package doctor

import (
	"os"
	"testing"
)

// Ryoku's live NixOS session exports RYOKU_UPDATE_BACKEND=nix.
//
// Most Doctor tests exercise upstream/portable behaviour and must not silently
// change meaning depending on the developer's host session. Tests which need
// the Nix policy explicitly opt in with t.Setenv.
func TestMain(m *testing.M) {
	old, had := os.LookupEnv("RYOKU_UPDATE_BACKEND")
	_ = os.Setenv("RYOKU_UPDATE_BACKEND", "pacman")

	code := m.Run()

	if had {
		_ = os.Setenv("RYOKU_UPDATE_BACKEND", old)
	} else {
		_ = os.Unsetenv("RYOKU_UPDATE_BACKEND")
	}

	os.Exit(code)
}
