package sys

import (
	"os"
	"strings"
)

// NixBackend reports whether this Ryoku binary is running under the
// declarative NixOS integration.
//
// The Nix package wrapper sets RYOKU_UPDATE_BACKEND=nix, which is a better
// signal than probing /etc/NIXOS: unit tests and upstream development builds
// can still exercise the Arch behaviour even when they happen to run on a
// NixOS development machine.
func NixBackend() bool {
	backend := strings.ToLower(
		strings.TrimSpace(os.Getenv("RYOKU_UPDATE_BACKEND")),
	)

	switch backend {
	case "nix":
		return true
	case "pacman", "arch":
		return false
	}

	// The NixOS module installs this marker declaratively. It covers direct
	// invocations that bypass the packaged wrapper or sessions whose imported
	// environment predates RYOKU_UPDATE_BACKEND.
	_, err := os.Stat("/etc/ryoku/nix-system-package-count")
	return err == nil
}
