package main

import (
	"context"
	"os"
	"strings"
	"sync"
	"testing"
)

// stubPackageManager pins the detected package manager for one test, since the
// real one asks the host seam.
func stubPackageManager(t *testing.T, name string) {
	t.Helper()
	previous := runningPackageManager
	runningPackageManager = sync.OnceValue(func() string { return name })
	t.Cleanup(func() { runningPackageManager = previous })
}

func TestProductPackageManagerGate(t *testing.T) {
	stubPackageManager(t, "xbps")
	if ok, _ := productPackageManagerGate(nil); !ok {
		t.Error("a product that declares no package manager must run everywhere")
	}
	if ok, _ := productPackageManagerGate([]string{"pacman"}); ok {
		t.Error("a pacman-only product must not run on an xbps host")
	}
	if ok, _ := productPackageManagerGate([]string{"pacman", "XBPS"}); !ok {
		t.Error("a product listing this host's package manager must run here")
	}
	stubPackageManager(t, "")
	if ok, _ := productPackageManagerGate([]string{"pacman"}); !ok {
		t.Error("an unreadable host must not hide content")
	}
}

func TestProductEntryItemMarksAnotherEdition(t *testing.T) {
	stubWindowManager(t, "")
	stubPackageManager(t, "dnf")
	entry := ProductEntry{ID: "demo", Name: "Demo", PackageManagers: []string{"pacman"},
		PackageManagersReason: "Builds from the AUR, which only Arch-based Ryoku has."}
	item, err := productEntryItem("", "plugins", entry)
	if err != nil {
		t.Fatal(err)
	}
	if !item.Unavailable || !item.UnavailableEdition || item.UnavailableReason != entry.PackageManagersReason {
		t.Fatalf("item = unavailable %v edition %v reason %q", item.Unavailable, item.UnavailableEdition, item.UnavailableReason)
	}
	if len(item.RequiredPackageManagers) != 1 || item.RequiredPackageManagers[0] != "pacman" {
		t.Fatalf("requiredPackageManagers = %v", item.RequiredPackageManagers)
	}

	// Both gates failing: the window manager is named, since switching it is
	// something the user can do; the edition flag stays clear so the chip agrees.
	stubWindowManager(t, runningManager)
	both := entry
	both.WindowManager = declaredManager
	if item, _ = productEntryItem("", "plugins", both); item.UnavailableEdition || !strings.Contains(item.UnavailableReason, runningManager) {
		t.Fatalf("both gates = edition %v reason %q", item.UnavailableEdition, item.UnavailableReason)
	}
	stubWindowManager(t, "")

	entry.PackageManagersReason = ""
	if item, _ = productEntryItem("", "plugins", entry); item.UnavailableReason == "" {
		t.Fatal("a gate without a catalogue sentence still needs a reason")
	}

	stubPackageManager(t, "pacman")
	if item, _ = productEntryItem("", "plugins", entry); item.Unavailable {
		t.Fatal("a pacman-only product is unavailable on pacman")
	}
}

// A product for another edition is refused before any byte is fetched, so a
// client that asks anyway cannot install what the store greys out.
func TestOtherEditionRefusesDownloadBeforeFetch(t *testing.T) {
	setTransactionXDG(t)
	stubWindowManager(t, "")
	stubPackageManager(t, "xbps")
	ctx := context.Background()

	other := newTransactionFixture(t, "1.0.0", []byte("payload\n"), []byte("payload\n"), func(e *ProductEntry) {
		e.PackageManagers = []string{"pacman"}
		e.PackageManagersReason = "Needs the AUR."
	})
	err := installProduct(ctx, other.cache, "plugins", other.entry)
	if err == nil || !strings.Contains(err.Error(), "Needs the AUR.") {
		t.Fatalf("refusal = %v", err)
	}
	if other.requests.hit("/plugins/demo/product-manifest.json") {
		t.Error("refused install fetched the product manifest")
	}
	if _, err := os.Stat(installedPluginPath()); !os.IsNotExist(err) {
		t.Errorf("refused install wrote to the destination: %v", err)
	}
}

// The revision moves when an item gains an edition gate, and stays put for
// items without one.
func TestGateFingerprintCarriesPackageManagersOnlyWhenDeclared(t *testing.T) {
	plain := Item{Category: "plugins", ID: "demo", Version: "1"}
	gated := plain
	gated.RequiredPackageManagers = []string{"pacman"}
	if gateFingerprint(&plain) != "any\x1factive" {
		t.Fatalf("plain fingerprint = %q", gateFingerprint(&plain))
	}
	if gateFingerprint(&gated) == gateFingerprint(&plain) {
		t.Fatal("an edition gate did not change the fingerprint")
	}
}

func TestBundlePackageTableFollowsTheEdition(t *testing.T) {
	cases := map[string]string{"xbps": "bundles/packages/void.tsv", "dnf": "bundles/packages/fedora.tsv", "pacman": ""}
	for manager, want := range cases {
		if got := bundlePackageTableRel(manager); got != want {
			t.Errorf("bundlePackageTableRel(%q) = %q, want %q", manager, got, want)
		}
	}
}
