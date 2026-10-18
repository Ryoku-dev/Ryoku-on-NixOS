package doctor

import (
	"strings"
	"testing"
)

func TestNixHostOwnedReconcilersDoNotMutateHost(t *testing.T) {
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")

	tests := []struct {
		name string
		run  func(bool) recResult
	}{
		{"boot guard", reconcileBootGuard},
		{"pacman lock", reconcilePacmanLock},
		{"stale installer crypt mapper", reconcileStaleCryptMapper},
		{"ryoku package channel", reconcileRyokuChannel},
		{"ryoku package database", reconcileRyokuSyncDB},
		{"icon font", reconcileIconFont},
		{"pacnew repair", reconcilePacnew},
		{"conflicting package files", reconcileConflictingRyokuFiles},
		{"snapper", reconcileSnapper},
		{"snapper cleanup", reconcileSnapperCleanup},
		{"quickshell", reconcileQuickshell},
		{"qmk", reconcileQMK},
		{"asus aura", reconcileAsusAura},
		{"lockscreen", reconcileLockscreen},
		{"lockscreen drift", reconcileLockscreenDrift},
		{"portal routing", reconcilePortalRouting},
		{"greeter theme", reconcileGreeterTheme},
		{"greeter display server", reconcileGreeterDisplayServer},
		{"greeter cursor", reconcileGreeterCursor},

		{"alongside boot entry", reconcileAlongsideBootEntry},
		{"flatpak remote", reconcileFlatpakRemote},
		{"kepler nvidia", reconcileKeplerNvidia},
		{"nvidia modeset", reconcileNvidiaModeset},
		{"nvidia pacman guard", reconcileNvidiaGuardHook},
		{"fedora legacy boot", reconcileFedoraLegacyBoot},
		{"limine layout", reconcileLimineLayout},
		{"limine boot entry", reconcileLimineBootEntry},
		{"limine uki tree", reconcileLimineUKITree},
		{"limine os name", reconcileLimineOSName},
		{"limine autoboot", reconcileLimineAutoboot},
		{"limine kernel images", reconcileLimineKernelImages},
		{"pacman candy", reconcilePacmanCandy},
		{"updatedb prune", reconcileUpdatedbPrune},
		{"zen system policy", reconcileZen},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Deliberately use fix mode, not check-only. The Nix guard must
			// intercept before any persistent host mutation can happen.
			got := tt.run(false)

			text := strings.ToLower(got.detail + " " + got.remedy)

			if !strings.Contains(text, "nixos") &&
				!strings.Contains(text, "declarative") {
				t.Fatalf(
					"Nix policy was not visible in result: %+v",
					got,
				)
			}

			for _, forbidden := range []string{
				"sudo pacman",
				"pacman -s",
				"systemctl enable",
				"systemctl disable",
				"loginctl enable-linger",
				"usermod",
			} {
				if strings.Contains(text, forbidden) {
					t.Fatalf(
						"Nix policy exposed host mutation %q: %+v",
						forbidden,
						got,
					)
				}
			}
		})
	}
}
