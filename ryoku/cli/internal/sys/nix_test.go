package sys

import "testing"

func TestNixBackend(t *testing.T) {
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")

	if !NixBackend() {
		t.Fatal("NixBackend() = false, want true")
	}

	t.Setenv("RYOKU_UPDATE_BACKEND", "pacman")

	if NixBackend() {
		t.Fatal("NixBackend() = true for non-Nix backend")
	}
}
