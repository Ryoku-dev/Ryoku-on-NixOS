package updater

import (
	"context"
	"testing"

	"ryoku-cli/internal/ryotunesrelease"
)

func TestNativePackageManagersSkipStandaloneRyotunesLane(t *testing.T) {
	for _, manager := range []string{"dnf", "xbps"} {
		t.Run(manager, func(t *testing.T) {
			oldCheck := checkRyotunesRelease
			oldUpgrade := upgradeRyotunesRelease
			t.Cleanup(func() {
				checkRyotunesRelease = oldCheck
				upgradeRyotunesRelease = oldUpgrade
			})
			t.Setenv("RYOKU_HOST_PKGMGR", manager)
			checkRyotunesRelease = func(context.Context) (ryotunesrelease.Status, error) {
				t.Fatal("native repository lane queried the standalone Arch release")
				return ryotunesrelease.Status{}, nil
			}
			upgradeRyotunesRelease = func(context.Context) (ryotunesrelease.Status, error) {
				t.Fatal("native repository lane installed the standalone Arch release")
				return ryotunesrelease.Status{}, nil
			}

			upgradeRyotunes()
			report := statusReport{}
			addRyotunesUpdate(&report)
			if len(report.Updates) != 0 || report.Behind != 0 || report.Available {
				t.Fatalf("standalone lane changed native report: %#v", report)
			}
		})
	}
}
