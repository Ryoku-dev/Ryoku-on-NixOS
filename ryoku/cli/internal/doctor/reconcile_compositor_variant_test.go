package doctor

import (
	"slices"
	"strings"
	"testing"

	"ryoku-cli/internal/host"

	wm "ryoku-wm"
)

type compositorVariantFixture struct {
	pkg       string
	installed map[string]bool
	installs  [][]string
}

func stubCompositorVariant(t *testing.T, offered, present, available bool) *compositorVariantFixture {
	t.Helper()
	providers := wm.Providers()
	if len(providers) == 0 {
		t.Fatal("window-manager seam has no providers")
	}
	provider := providers[len(providers)-1]
	pkg := wm.VariantPackage(provider)
	if pkg == "" {
		t.Fatalf("provider %q has no desktop variant package", provider)
	}

	oldDirs := compositorVariantSessionDirs
	oldOffered := compositorVariantSessionOffered
	oldManager := doctorPackageManager
	oldInstalled := doctorPackageInstalled
	oldAvailability := doctorPackageAvailability
	oldInstall := doctorPackageInstall
	t.Cleanup(func() {
		compositorVariantSessionDirs = oldDirs
		compositorVariantSessionOffered = oldOffered
		doctorPackageManager = oldManager
		doctorPackageInstalled = oldInstalled
		doctorPackageAvailability = oldAvailability
		doctorPackageInstall = oldInstall
	})

	sessionDir := t.TempDir()
	compositorVariantSessionDirs = func() []string { return []string{sessionDir} }
	compositorVariantSessionOffered = func(name string, dirs []string) bool {
		if !slices.Equal(dirs, []string{sessionDir}) {
			t.Fatalf("session dirs = %v, want injected path %q", dirs, sessionDir)
		}
		return offered && name == provider
	}
	doctorPackageManager = func() (host.PackageManager, error) { return host.DNF, nil }

	fixture := &compositorVariantFixture{
		pkg:       pkg,
		installed: map[string]bool{pkg: present},
	}
	doctorPackageInstalled = func(name string) bool { return fixture.installed[name] }
	doctorPackageAvailability = func(name string) int {
		if name == pkg && !available {
			return host.ExitNotProvided
		}
		return host.ExitOK
	}
	doctorPackageInstall = func(names ...string) int {
		fixture.installs = append(fixture.installs, append([]string(nil), names...))
		for _, name := range names {
			fixture.installed[name] = true
		}
		return host.ExitOK
	}
	return fixture
}

func TestReconcileCompositorVariantInstallsOfferedMissingVariant(t *testing.T) {
	fixture := stubCompositorVariant(t, true, false, true)

	check := reconcileCompositorVariants(true)
	if check.status != recWarn || !strings.Contains(check.detail, "bare") {
		t.Fatalf("check = %s %q, want warning that the session will be bare", check.status.label(), check.detail)
	}
	if len(fixture.installs) != 0 {
		t.Fatal("check-only installed a desktop variant")
	}

	repair := reconcileCompositorVariants(false)
	if repair.status != recFixed {
		t.Fatalf("repair = %s %q, want fixed", repair.status.label(), repair.detail)
	}
	if len(fixture.installs) != 1 || !slices.Equal(fixture.installs[0], []string{fixture.pkg}) {
		t.Fatalf("install calls = %v, want one install of %q", fixture.installs, fixture.pkg)
	}
}

func TestReconcileCompositorVariantUnavailableIsANote(t *testing.T) {
	fixture := stubCompositorVariant(t, true, false, false)

	for _, checkOnly := range []bool{true, false} {
		result := reconcileCompositorVariants(checkOnly)
		if result.status != recNote || !strings.Contains(result.detail, "not available") || !strings.Contains(result.detail, "bare") {
			t.Fatalf("checkOnly=%t result = %s %q, want unavailable bare-session note", checkOnly, result.status.label(), result.detail)
		}
	}
	if len(fixture.installs) != 0 {
		t.Fatalf("unavailable variant triggered installs: %v", fixture.installs)
	}
}

func TestReconcileCompositorVariantPresentIsOK(t *testing.T) {
	fixture := stubCompositorVariant(t, true, true, true)

	if result := reconcileCompositorVariants(false); result.status != recOK {
		t.Fatalf("result = %s %q, want ok", result.status.label(), result.detail)
	}
	if len(fixture.installs) != 0 {
		t.Fatalf("present variant triggered installs: %v", fixture.installs)
	}
}

func TestReconcileCompositorVariantIgnoresAbsentDesktop(t *testing.T) {
	fixture := stubCompositorVariant(t, false, false, true)
	doctorPackageManager = func() (host.PackageManager, error) {
		t.Fatal("an absent desktop must not trigger package checks")
		return host.DNF, nil
	}
	doctorPackageInstalled = func(string) bool {
		t.Fatal("an absent desktop must not trigger installed-package checks")
		return false
	}

	if result := reconcileCompositorVariants(false); result.status != recOK {
		t.Fatalf("result = %s %q, want ok", result.status.label(), result.detail)
	}
	if len(fixture.installs) != 0 {
		t.Fatalf("absent desktop triggered installs: %v", fixture.installs)
	}
}
