package main

import (
	"os"
	"strings"
	"testing"
)

func TestNixOSReleaseDetection(t *testing.T) {
	for _, tc := range []struct {
		name, release string
		nixos         bool
	}{
		{"nixos", "NAME=NixOS\nID=nixos\n", true},
		{"quoted", "ID=\"nixos\"\n", true},
		{"arch", "ID=arch\nID_LIKE=archlinux\n", false},
		{"fedora", "ID=fedora\n", false},
		{"similar name", "NAME=Not nixos\nID=arch\n", false},
		{"missing", "NAME=Linux\n", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := isNixOSRelease([]byte(tc.release)); got != tc.nixos {
				t.Fatalf("isNixOSRelease(%q) = %v, want %v", tc.release, got, tc.nixos)
			}
		})
	}
}

func TestFlatpakCatalogueIsAbsentOnlyOnNixOS(t *testing.T) {
	for _, tc := range []struct {
		name  string
		nixos bool
	}{
		{"nixos", true},
		{"other Linux", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			provs := providersForOS(tc.nixos)
			_, found := providerFor(provs, flatpakCategory)
			if found == tc.nixos {
				t.Fatalf("flatpak provider found=%v on nixos=%v", found, tc.nixos)
			}
			cat := BuildCatalog(t.Context(), []Provider{fakeProvider{category: Category{ID: "barstyles"}}}, false)
			if len(cat.Categories) != 1 || cat.Categories[0].ID != "barstyles" {
				t.Fatal("non-flatpak categories must remain available")
			}
		})
	}
	if got := storeSection(flatpakCategory); got == isNixOS() {
		t.Fatalf("flatpak route enabled=%v on nixos=%v", got, isNixOS())
	}
	if _, err := os.ReadFile("/etc/os-release"); err == nil && isNixOS() {
		if err := runOpen([]string{flatpakCategory}); err == nil || !strings.Contains(err.Error(), "valid section") {
			t.Fatalf("NixOS flatpak deep link should be rejected: %v", err)
		}
	}
}
