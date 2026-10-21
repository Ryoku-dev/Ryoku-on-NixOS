package main

import (
	"context"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
)

// Which package manager runs this host, and whether a catalogue product works
// with it.
//
// Ryoku runs on Arch and CachyOS (pacman), Fedora (dnf) and Void (xbps). A
// catalogue item that cannot be ported to every edition (AUR-only software, an
// Arch-only repository) declares the package managers it runs on (registry
// `packageManagers`, the names `ryoku-host pkgmgr` prints). The host reports
// itself through the seam and the answer is compared with what the item
// declared, so an edition is never guessed and a new one needs no change here.
// Like the window manager gate, an item that does not fit stays listed, keeps an
// installed copy removable, and is refused for install and update.

// runningPackageManager is the host's package manager, cached for the process.
// Empty when it cannot be read, which gates nothing.
var runningPackageManager = sync.OnceValue(func() string {
	out, err := exec.Command("ryoku-host", "pkgmgr").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
})

// productPackageManagerGate reports whether an item limited to `required` runs
// here. An item that declares nothing runs everywhere.
func productPackageManagerGate(required []string) (ok bool, running string) {
	if len(required) == 0 {
		return true, ""
	}
	running = runningPackageManager()
	if running == "" {
		return true, ""
	}
	for _, name := range required {
		if strings.EqualFold(strings.TrimSpace(name), running) {
			return true, running
		}
	}
	return false, running
}

// packageManagerReason is the line a user reads for an item this host cannot
// run: the catalogue's own sentence, else a plain one.
func packageManagerReason(declared string) string {
	if declared = strings.TrimSpace(declared); declared != "" {
		return declared
	}
	return "Not available on this edition of Ryoku."
}

// bundlePackageTableRel is the catalogue table that names bundle packages on
// this host's edition, empty on pacman hosts, whose names are the catalogue's.
func bundlePackageTableRel(manager string) string {
	switch manager {
	case "xbps":
		return "bundles/packages/void.tsv"
	case "dnf":
		return "bundles/packages/fedora.tsv"
	}
	return ""
}

// ensureBundlePackageTable caches this edition's bundle package table and
// returns its path, or "" when the host needs none or no copy can be had. The
// bundle actuator hands it to ryoku-host as the overlay under Ryoku's own
// edition table.
func ensureBundlePackageTable(ctx context.Context, cache *Cache, refresh bool) string {
	rel := bundlePackageTableRel(runningPackageManager())
	if rel == "" {
		return ""
	}
	if _, _, err := cache.Fetch(ctx, rel, refresh); err != nil {
		return ""
	}
	return filepath.Join(cache.dir, rel)
}
