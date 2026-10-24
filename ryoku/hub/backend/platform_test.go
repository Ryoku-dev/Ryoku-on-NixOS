package main

import (
	"strings"
	"testing"
)

func TestNixManagedHost(t *testing.T) {
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")
	if !nixManagedHost() {
		t.Fatal("nixManagedHost() = false, want true")
	}

	t.Setenv("RYOKU_UPDATE_BACKEND", "pacman")
	if nixManagedHost() {
		t.Fatal("nixManagedHost() = true for non-Nix backend")
	}
}

func TestNixMutationsAreRefused(t *testing.T) {
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")

	if err := runShellPref([]string{"set", "zsh"}); err == nil || !strings.Contains(err.Error(), "managed declaratively on NixOS") {
		t.Fatalf("shell mutation was not refused on NixOS: %v", err)
	}
	if err := runShellPref([]string{"apply", "zsh"}); err == nil || !strings.Contains(err.Error(), "refusing usermod") {
		t.Fatalf("privileged shell mutation was not refused on NixOS: %v", err)
	}
	if err := runGpuApply([]string{"enable", "--dry-run"}); err == nil || !strings.Contains(err.Error(), "NixOS") {
		t.Fatalf("GPU passthrough mutation was not refused on NixOS: %v", err)
	}
}
