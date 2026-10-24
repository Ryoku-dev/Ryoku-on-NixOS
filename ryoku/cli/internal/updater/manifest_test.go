package updater

import (
	"path/filepath"
	"reflect"
	"testing"

	"ryoku-cli/internal/ryokumanifest"
)

func TestPlanManifestFirstRunRecordsBaselineOnly(t *testing.T) {
	next := &ryokumanifest.Manifest{
		Base:       []string{"base"},
		FirstParty: []string{"ryoku-desktop"},
	}
	plan := PlanManifest(nil, nil, next, map[string]bool{"base": true})
	if len(plan.Install) != 0 || len(plan.AUR) != 0 || len(plan.UserGone) != 0 {
		t.Fatalf("first run changed state: %+v", plan)
	}
	// The gap the box has against the release is reported, not acted on.
	if !reflect.DeepEqual(plan.Untracked, []string{"ryoku-desktop"}) {
		t.Errorf("untracked = %v, want [ryoku-desktop]", plan.Untracked)
	}
}

func TestPlanManifestDeliversNeverPresentNames(t *testing.T) {
	// The user's complaint in one function: a package the release always named
	// but this box never received must self-heal, not wait for a release that
	// happens to "add" it.
	prev := &ryokumanifest.Manifest{Base: []string{"base"}, Dev: []string{"go"}}
	next := &ryokumanifest.Manifest{Base: []string{"base"}, Dev: []string{"go"}}
	installed := map[string]bool{"base": true} // go never landed here
	plan := PlanManifest(prev, map[string]bool{"base": true}, next, installed)
	if !reflect.DeepEqual(plan.Install, []string{"go"}) {
		t.Errorf("install = %v, want [go]", plan.Install)
	}
}

func TestPlanManifestRespectsUserRemovalAfterBaseline(t *testing.T) {
	prev := &ryokumanifest.Manifest{Base: []string{"base"}, Dev: []string{"go"}}
	next := prev
	// go was present when the baseline was saved and is gone now: the user
	// removed it, and no later update puts it back.
	plan := PlanManifest(prev, map[string]bool{"base": true, "go": true}, next,
		map[string]bool{"base": true})
	if len(plan.Install) != 0 {
		t.Errorf("install = %v; a user removal must stay removed", plan.Install)
	}
	if !reflect.DeepEqual(plan.UserGone, []string{"go"}) {
		t.Errorf("userGone = %v, want [go]", plan.UserGone)
	}
}

func TestPlanManifestRoutesAURLaneBestEffort(t *testing.T) {
	prev := &ryokumanifest.Manifest{}
	next := &ryokumanifest.Manifest{AUR: []string{"some-aur-tool"}}
	plan := PlanManifest(prev, map[string]bool{}, next, map[string]bool{})
	if !reflect.DeepEqual(plan.AUR, []string{"some-aur-tool"}) {
		t.Errorf("aur = %v, want [some-aur-tool]", plan.AUR)
	}
	if len(plan.Install) != 0 {
		t.Errorf("install = %v; AUR names must not go through pacman", plan.Install)
	}
}

func TestPlanManifestLeavesProvisionedLaneToShippedApps(t *testing.T) {
	// reconcileShippedApps owns the deliver-once apps. If PlanManifest also
	// installed them, one update would run two pacman transactions over the
	// same names.
	prev := &ryokumanifest.Manifest{}
	next := &ryokumanifest.Manifest{Provisioned: []string{"kitty"}}
	plan := PlanManifest(prev, map[string]bool{}, next, map[string]bool{})
	if len(plan.Install) != 0 {
		t.Errorf("install = %v; the provisioned lane is not this reconciler's", plan.Install)
	}
}

func TestPlanManifestNeverPullsRashinOntoABoxWithoutIt(t *testing.T) {
	// Rashin is a deliver-once app and prowl only its dependency: a box whose
	// installer left Rashin out must not get either back from the first-party
	// lane, on the run that records the baseline or on any run after it.
	m := &ryokumanifest.Manifest{
		Base:        []string{"base"},
		FirstParty:  []string{"ryoku-desktop", "ryoku-rashin", "prowl"},
		Provisioned: ryokumanifest.AppNames(),
	}
	installed := map[string]bool{"base": true, "ryoku-desktop": true}
	plan := PlanManifest(m, installed, m, installed)
	for _, n := range plan.Install {
		if n == "ryoku-rashin" || n == "prowl" {
			t.Fatalf("install = %v; an optional Rashin must not come back through the manifest", plan.Install)
		}
	}
}

func TestPlanManifestReportsRetiredNames(t *testing.T) {
	prev := &ryokumanifest.Manifest{Dev: []string{"dropped-tool"}}
	next := &ryokumanifest.Manifest{}
	plan := PlanManifest(prev, map[string]bool{"dropped-tool": true}, next,
		map[string]bool{"dropped-tool": true})
	if !reflect.DeepEqual(plan.Retired, []string{"dropped-tool"}) {
		t.Errorf("retired = %v, want [dropped-tool]", plan.Retired)
	}
	if len(plan.UserGone) != 0 {
		t.Errorf("userGone = %v; a retired name is the release's decision, not the user's", plan.UserGone)
	}
}

func TestSatisfiedByProvidersKeepsTheBoxsOwnProvider(t *testing.T) {
	// A CachyOS box carrying rustup and tuned-ppd: pacman counts rust and
	// power-profiles-daemon as installed through them, and installing the stock
	// package over either conflicts under --noconfirm on every update. go is
	// satisfied by nothing, so it stays a real gap the converge delivers.
	t.Setenv("RYOKU_HOST_PKGMGR", "pacman")
	bin := t.TempDir()
	writeExec(t, filepath.Join(bin, "pacman"), "#!/bin/sh\n[ \"$1\" = -T ] || exit 2\nshift\nrc=0\nfor n; do case $n in rust|power-profiles-daemon) ;; *) echo \"$n\"; rc=127;; esac; done\nexit $rc\n")
	t.Setenv("PATH", bin)
	m := ryokumanifest.Manifest{Base: []string{"base", "rust", "power-profiles-daemon"}, Dev: []string{"go"}}

	installed := SatisfiedByProviders(m, map[string]bool{"base": true})
	if want := map[string]bool{"base": true, "rust": true, "power-profiles-daemon": true}; !reflect.DeepEqual(installed, want) {
		t.Fatalf("installed = %v, want %v", installed, want)
	}
	plan := PlanManifest(&m, map[string]bool{"base": true}, &m, installed)
	if !reflect.DeepEqual(plan.Install, []string{"go"}) {
		t.Fatalf("install = %v, want [go]: a provided name must not be installed over its provider", plan.Install)
	}

	writeExec(t, filepath.Join(bin, "pacman"), "#!/bin/sh\nexit 1\n")
	if got := SatisfiedByProviders(m, map[string]bool{"base": true}); !reflect.DeepEqual(got, map[string]bool{"base": true}) {
		t.Fatalf("a failed pacman -T widened the set to %v", got)
	}
}

func TestFedoraPackageSetsUseRPMAndDNFUserInstalled(t *testing.T) {
	t.Setenv("RYOKU_HOST_PKGMGR", "dnf")
	bin := t.TempDir()
	writeExec(t, filepath.Join(bin, "rpm"), "#!/bin/sh\ncase \"$*\" in *PROVIDENAME*) ;; *) exit 2 ;; esac\n"+
		"printf 'ryoku-desktop\\nquickshell\\npower-profiles-daemon\\nppd-service\\nfont(dejavu sans)\\n'\n")
	writeExec(t, filepath.Join(bin, "dnf5"), "#!/bin/sh\n[ \"$1 $2\" = 'repoquery -y' ] || exit 2\nprintf 'ryoku-desktop\\n'\n")
	t.Setenv("PATH", bin)

	installed, err := packageSet(false)
	if err != nil {
		t.Fatal(err)
	}
	if want := map[string]bool{"ryoku-desktop": true, "quickshell": true, "power-profiles-daemon": true,
		"ppd-service": true, "font(dejavu sans)": true}; !reflect.DeepEqual(installed, want) {
		t.Fatalf("installed = %#v, want %#v", installed, want)
	}
	explicit, err := packageSet(true)
	if err != nil {
		t.Fatal(err)
	}
	if want := map[string]bool{"ryoku-desktop": true}; !reflect.DeepEqual(explicit, want) {
		t.Fatalf("explicit = %#v, want %#v", explicit, want)
	}
}

func TestPlanManifestDoesNotInstallChoiceAbsentFromNext(t *testing.T) {
	// Older baselines named every browser, so a box that chose Chromium had
	// never-present Firefox marked as a gap. Once choices leave the manifest,
	// that old baseline must not make convergence install Firefox.
	prev := &ryokumanifest.Manifest{Base: []string{"base", "firefox"}}
	next := &ryokumanifest.Manifest{Base: []string{"base"}}
	plan := PlanManifest(prev, map[string]bool{"base": true}, next, map[string]bool{"base": true})
	if len(plan.Install) != 0 {
		t.Errorf("install = %v; a package absent from the new manifest must stay absent", plan.Install)
	}
}
