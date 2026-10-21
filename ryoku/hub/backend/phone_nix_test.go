package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNixPhoneAndRashinKeepSystemOwnership(t *testing.T) {
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	if err := privileged("phone", "enable"); err == nil || !strings.Contains(err.Error(), "NixOS") {
		t.Fatalf("Nix setup reached privileged host: %v", err)
	}
	if err := recordProvisioned(rashinPackage); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(state, "ryoku", "provisioned")); !os.IsNotExist(err) {
		t.Fatalf("Nix wrote mutable package ledger: %v", err)
	}
}
