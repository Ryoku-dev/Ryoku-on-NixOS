package doctor

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"ryoku-cli/internal/host"
	"testing"
)

// stubLimineBootGates forces the managed-boot and package-installed gates the
// dependent reconcilers consult, so a direct call reaches its probe logic on a
// host that has neither the limine tooling nor ryoku-desktop installed (CI).
func stubLimineBootGates(t *testing.T) {
	t.Helper()
	oldManaged := limineManagedBoot
	oldInstalled := doctorPackageInstalled
	oldLimine := liminePkgInstalled
	oldManager := doctorPackageManager
	limineManagedBoot = func() bool { return true }
	doctorPackageInstalled = func(string) bool { return true }
	liminePkgInstalled = func(string) bool { return true }
	doctorPackageManager = func() (host.PackageManager, error) { return host.Pacman, nil }
	t.Cleanup(func() {
		limineManagedBoot = oldManaged
		doctorPackageInstalled = oldInstalled
		liminePkgInstalled = oldLimine
		doctorPackageManager = oldManager
	})
}

// TestProbeFile verifies that probeFile correctly distinguishes readable files,
// genuinely missing files (ENOENT), and permission-denied files/directories (EACCES)
// without needing root privileges.
func TestProbeFile(t *testing.T) {
	dir := t.TempDir()

	// 1. Readable file
	readablePath := filepath.Join(dir, "readable.conf")
	content := "timeout: 3\ndefault_entry: 1\n"
	if err := os.WriteFile(readablePath, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	gotContent, exists, readable := probeFile(readablePath)
	if !exists || !readable || gotContent != content {
		t.Errorf("readable file: got (%q, %v, %v), want (%q, true, true)", gotContent, exists, readable, content)
	}

	// 2. Genuinely missing file (ENOENT)
	missingPath := filepath.Join(dir, "nonexistent.conf")
	gotContent, exists, readable = probeFile(missingPath)
	if exists || readable || gotContent != "" {
		t.Errorf("missing file: got (%q, %v, %v), want (\"\", false, false)", gotContent, exists, readable)
	}

	// 3. Directory path (EISDIR, a non-ENOENT error that fails for both normal users and root)
	dirPath := filepath.Join(dir, "test_dir")
	if err := os.Mkdir(dirPath, 0o755); err != nil {
		t.Fatal(err)
	}
	gotContent, exists, readable = probeFile(dirPath)
	if !exists || readable || gotContent != "" {
		t.Errorf("directory probe: got (%q, %v, %v), want (\"\", true, false)", gotContent, exists, readable)
	}

	// 4. Permission-denied file (mode 0000)
	if os.Geteuid() == 0 {
		t.Log("skipping DAC permission-denied file test when running as root")
	} else {
		unreadableFile := filepath.Join(dir, "unreadable.conf")
		if err := os.WriteFile(unreadableFile, []byte("secret"), 0o000); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.Chmod(unreadableFile, 0o600) })

		gotContent, exists, readable = probeFile(unreadableFile)
		if !exists || readable || gotContent != "" {
			t.Errorf("unreadable file: got (%q, %v, %v), want (\"\", true, false)", gotContent, exists, readable)
		}
	}

	// 5. Permission-denied parent directory (simulating /boot mode 0700 for non-root)
	if os.Geteuid() == 0 {
		t.Log("skipping DAC permission-denied directory test when running as root")
	} else {
		protectedDir := filepath.Join(dir, "protected_boot")
		if err := os.Mkdir(protectedDir, 0o700); err != nil {
			t.Fatal(err)
		}
		inProtected := filepath.Join(protectedDir, "limine.conf")
		if err := os.WriteFile(inProtected, []byte("timeout: 5\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		// Chmod directory to 0000 so traversal fails with EACCES
		if err := os.Chmod(protectedDir, 0o000); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.Chmod(protectedDir, 0o700) })

		gotContent, exists, readable = probeFile(inProtected)
		if !exists || readable || gotContent != "" {
			t.Errorf("traversal-denied file: got (%q, %v, %v), want (\"\", true, false)", gotContent, exists, readable)
		}
	}
}

// TestGatherLimineLayoutStateDistinguishesEACCESFromENOENT checks that
// gatherLimineLayoutState marks espConfExists=true and espConfReadable=false
// when /boot/limine.conf is permission-denied, but leaves both false when missing.
func TestGatherLimineLayoutStateDistinguishesEACCESFromENOENT(t *testing.T) {
	dir := t.TempDir()
	stubLimineBootGates(t)

	origESP, origShadow, origTool, origLegacy, origPkg, origProbe := limineESPConf, limineShadow, limineToolEFI, limineLegacyEFI, liminePkgInstalled, liminePathProbe
	t.Cleanup(func() {
		limineESPConf, limineShadow, limineToolEFI, limineLegacyEFI, liminePkgInstalled, liminePathProbe = origESP, origShadow, origTool, origLegacy, origPkg, origProbe
	})
	liminePkgInstalled = func(string) bool { return true }
	limineShadow = filepath.Join(dir, "shadow_missing.conf")
	limineToolEFI = filepath.Join(dir, "tool_missing.efi")
	limineLegacyEFI = filepath.Join(dir, "legacy_missing.efi")
	liminePathProbe = func(string) (bool, error) { return false, nil }

	// Case A: Missing file (ENOENT)
	limineESPConf = filepath.Join(dir, "missing.conf")
	stMissing := gatherLimineLayoutState()
	if stMissing.espConfExists || stMissing.espConfReadable {
		t.Errorf("missing config: got exists=%v, readable=%v; want false, false",
			stMissing.espConfExists, stMissing.espConfReadable)
	}
	outcome, _ := planLimineLayout(stMissing)
	if outcome != limineLayoutSkip {
		t.Errorf("missing config plan: got outcome %d, want limineLayoutSkip (%d)", outcome, limineLayoutSkip)
	}

	// Case B: Permission denied (EACCES) via mode 0000 file
	if os.Geteuid() == 0 {
		t.Log("skipping permission-denied layout test when running as root (root bypasses DAC permissions)")
	} else {
		unreadable := filepath.Join(dir, "unreadable_limine.conf")
		if err := os.WriteFile(unreadable, []byte("timeout: 3\n"), 0o000); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.Chmod(unreadable, 0o600) })

		limineESPConf = unreadable
		stDenied := gatherLimineLayoutState()
		if !stDenied.espConfExists || stDenied.espConfReadable {
			t.Errorf("permission-denied config: got exists=%v, readable=%v; want true, false",
				stDenied.espConfExists, stDenied.espConfReadable)
		}
		outcome, _ := planLimineLayout(stDenied)
		if outcome != limineLayoutUnreadable {
			t.Errorf("permission-denied config plan: got outcome %d, want limineLayoutUnreadable (%d)", outcome, limineLayoutUnreadable)
		}

		res := reconcileLimineLayout(true)
		if res.status != recNote {
			t.Errorf("reconcileLimineLayout on permission-denied config: got status %d, want recNote (%d)", res.status, recNote)
		}
		if warns, fails := printFindings([]finding{{name: "limine boot menu layout", res: res}}, false); warns != 0 || fails != 0 {
			t.Errorf("permission-only layout inspection counted as health issue: warns=%d fails=%d", warns, fails)
		}
		if !strings.Contains(res.detail, "cannot read the limine config under /boot") {
			t.Errorf("unexpected detail: %s", res.detail)
		}
		if res.remedy != "sudo ryoku doctor --check" {
			t.Errorf("expected remedy 'sudo ryoku doctor --check', got %q", res.remedy)
		}
	}

	// Case C: Readable file
	readable := filepath.Join(dir, "readable_limine.conf")
	if err := os.WriteFile(readable, []byte("timeout: 3\ndefault_entry: 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	limineESPConf = readable
	stReadable := gatherLimineLayoutState()
	if !stReadable.espConfExists || !stReadable.espConfReadable || stReadable.espConf == "" {
		t.Errorf("readable config: got exists=%v, readable=%v, content=%q; want true, true, non-empty",
			stReadable.espConfExists, stReadable.espConfReadable, stReadable.espConf)
	}
}

func TestGatherLimineLayoutStateUsesEditionEFIPath(t *testing.T) {
	dir := t.TempDir()
	stubLimineBootGates(t)
	doctorPackageManager = func() (host.PackageManager, error) { return host.XBPS, nil }

	oldESP, oldShadow, oldProbe := limineESPConf, limineShadow, liminePathProbe
	t.Cleanup(func() {
		limineESPConf, limineShadow, liminePathProbe = oldESP, oldShadow, oldProbe
	})
	limineESPConf = filepath.Join(dir, "missing.conf")
	limineShadow = filepath.Join(dir, "missing-shadow.conf")
	probed := map[string]bool{}
	liminePathProbe = func(path string) (bool, error) {
		probed[path] = true
		return false, nil
	}

	gatherLimineLayoutState()
	if !probed[limineLegacyEFI] {
		t.Errorf("legacy EFI path was not probed: %v", probed)
	}
	if !probed["/boot/EFI/ryoku/BOOTX64.EFI"] {
		t.Errorf("Void EFI path was not probed: %v", probed)
	}
	if probed[limineToolEFI] {
		t.Errorf("Arch EFI path was probed on Void: %v", probed)
	}
}

// TestReconcileLimineBootEntryPermissions verifies that reconcileLimineBootEntry
// distinguishes permission-denied EFI binary from a genuinely missing one.
func TestReconcileLimineBootEntryPermissions(t *testing.T) {
	dir := t.TempDir()
	stubLimineBootGates(t)

	origTool, origPkg := limineToolEFI, liminePkgInstalled
	t.Cleanup(func() {
		limineToolEFI, liminePkgInstalled = origTool, origPkg
	})
	liminePkgInstalled = func(string) bool { return true }

	// Genuinely missing: skips with okRes ("not a limine-managed boot on this box")
	limineToolEFI = filepath.Join(dir, "missing.efi")
	resMissing := reconcileLimineBootEntry(true)
	if resMissing.status != recOK || !strings.Contains(resMissing.detail, "not a limine-managed boot") {
		t.Errorf("missing EFI binary: got %+v, want recOK (not limine-managed)", resMissing)
	}

	// Permission denied: reports an advisory note instead of a health issue.
	if os.Geteuid() == 0 {
		t.Log("skipping permission-denied EFI binary test when running as root (root bypasses DAC permissions)")
	} else {
		protectedDir := filepath.Join(dir, "protected_efi")
		if err := os.Mkdir(protectedDir, 0o700); err != nil {
			t.Fatal(err)
		}
		efiFile := filepath.Join(protectedDir, "limine_x64.efi")
		if err := os.WriteFile(efiFile, []byte("efi"), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chmod(protectedDir, 0o000); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.Chmod(protectedDir, 0o700) })

		limineToolEFI = efiFile
		resDenied := reconcileLimineBootEntry(true)
		if resDenied.status != recNote {
			t.Errorf("permission-denied EFI binary: got status %d, want recNote (%d)", resDenied.status, recNote)
		}
		if warns, fails := printFindings([]finding{{name: "limine boot entry", res: resDenied}}, false); warns != 0 || fails != 0 {
			t.Errorf("permission-only EFI inspection counted as health issue: warns=%d fails=%d", warns, fails)
		}
		if !strings.Contains(resDenied.detail, "cannot inspect") {
			t.Errorf("unexpected detail: %s", resDenied.detail)
		}
		if resDenied.remedy != "sudo ryoku doctor --check" {
			t.Errorf("expected remedy 'sudo ryoku doctor --check', got %q", resDenied.remedy)
		}
	}
}

// TestLimineDependentChecksStandAsideOnUnreadableConf tests that dependent Limine
// reconcilers do not report false-success or misleading findings when limineESPConf is unreadable.
func TestLimineDependentChecksStandAsideOnUnreadableConf(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("skipping permission-dependent test when running as root (root bypasses DAC permissions)")
	}
	dir := t.TempDir()
	stubLimineBootGates(t)

	origESP, origPkg, origDef := limineESPConf, liminePkgInstalled, limineDefaultsPath
	t.Cleanup(func() {
		limineESPConf, liminePkgInstalled, limineDefaultsPath = origESP, origPkg, origDef
	})
	liminePkgInstalled = func(string) bool { return true }

	defaultsFile := filepath.Join(dir, "default_limine")
	if err := os.WriteFile(defaultsFile, []byte("ENABLE_UKI=yes\nTARGET_OS_NAME=\"Ryoku\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	limineDefaultsPath = defaultsFile

	unreadable := filepath.Join(dir, "limine.conf")
	if err := os.WriteFile(unreadable, []byte("timeout: 3\n"), 0o000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(unreadable, 0o600) })
	limineESPConf = unreadable

	wantStandAside := "no readable " + unreadable + "; the layout reconciler owns that"

	// reconcileLimineUKITree
	if res := reconcileLimineUKITree(true); res.status != recNote || !strings.Contains(res.detail, "the layout reconciler owns that") {
		t.Errorf("reconcileLimineUKITree on unreadable: got %+v, want recNote with detail containing %q", res, wantStandAside)
	}

	// reconcileLimineKernelImages
	if res := reconcileLimineKernelImages(true); res.status != recNote || !strings.Contains(res.detail, "the layout reconciler owns that") {
		t.Errorf("reconcileLimineKernelImages on unreadable: got %+v, want recNote with detail containing %q", res, wantStandAside)
	}

	// reconcileLimineDeadEntries
	if res := reconcileLimineDeadEntries(true); res.status != recNote || !strings.Contains(res.detail, "the layout reconciler owns that") {
		t.Errorf("reconcileLimineDeadEntries on unreadable: got %+v, want recNote with detail containing %q", res, wantStandAside)
	}

	// reconcileLimineOSName
	if res := reconcileLimineOSName(true); res.status != recNote || !strings.Contains(res.detail, "the layout reconciler owns that") {
		t.Errorf("reconcileLimineOSName on unreadable: got %+v, want recNote with detail containing %q", res, wantStandAside)
	}

	// reconcileLimineAutoboot
	if res := reconcileLimineAutoboot(true); res.status != recNote || !strings.Contains(res.detail, "the layout reconciler owns that") {
		t.Errorf("reconcileLimineAutoboot on unreadable: got %+v, want recNote with detail containing %q", res, wantStandAside)
	}
}

// A box that boots through another build of limine-entry-tool (the plain tool
// CachyOS ships, or limine-dracut-support) has no package named
// limine-mkinitcpio-hook, and the hook conflicts with what it does have.
// Reading that as "hook missing" made the doctor attempt the same failing
// install on every run.
func TestLimineUKITreeAcceptsAnotherEntryToolBuild(t *testing.T) {
	dir := t.TempDir()
	stubLimineBootGates(t)
	origESP, origDef := limineESPConf, limineDefaultsPath
	t.Cleanup(func() { limineESPConf, limineDefaultsPath = origESP, origDef })
	liminePkgInstalled = func(name string) bool { return name == "limine" || name == "limine-entry-tool" }
	t.Setenv("PATH", t.TempDir())

	limineDefaultsPath = filepath.Join(dir, "default_limine")
	if err := os.WriteFile(limineDefaultsPath, []byte("ENABLE_UKI=yes\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	limineESPConf = filepath.Join(dir, "limine.conf")
	tree := "timeout: 3\ndefault_entry: 2\n\n/+Ryoku\n    comment: Ryoku\n//linux\n    protocol: efi\n"
	if err := os.WriteFile(limineESPConf, []byte(tree), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, checkOnly := range []bool{true, false} {
		if res := reconcileLimineUKITree(checkOnly); res.status != recOK {
			t.Fatalf("checkOnly=%v: got %s %q, want ok without installing limine-mkinitcpio-hook", checkOnly, res.status.label(), res.detail)
		}
	}
}

// TestGatherLimineLayoutStateInaccessibleEFIBinaries verifies that when EFI binaries
// cannot be inspected due to access or I/O errors, planLimineLayout yields limineLayoutUnreadable
// instead of silently assuming they are absent.
func TestGatherLimineLayoutStateInaccessibleEFIBinaries(t *testing.T) {
	dir := t.TempDir()
	stubLimineBootGates(t)

	origESP, origShadow, origTool, origLegacy, origPkg, origProbe := limineESPConf, limineShadow, limineToolEFI, limineLegacyEFI, liminePkgInstalled, liminePathProbe
	t.Cleanup(func() {
		limineESPConf, limineShadow, limineToolEFI, limineLegacyEFI, liminePkgInstalled, liminePathProbe = origESP, origShadow, origTool, origLegacy, origPkg, origProbe
	})
	liminePkgInstalled = func(string) bool { return true }

	confPath := filepath.Join(dir, "limine.conf")
	if err := os.WriteFile(confPath, []byte("timeout: 3\ndefault_entry: 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	limineESPConf = confPath
	limineShadow = filepath.Join(dir, "shadow_missing.conf")
	limineToolEFI = "/boot/EFI/limine/limine_x64.efi"
	limineLegacyEFI = "/boot/EFI/limine/limine.efi"

	// Simulate EIO error on legacy EFI binary
	liminePathProbe = func(p string) (bool, error) {
		switch p {
		case limineLegacyEFI:
			return false, syscall.EIO
		case limineToolEFI:
			return true, nil
		default:
			return false, nil
		}
	}

	st := gatherLimineLayoutState()
	if !st.legacyEFIInaccessible {
		t.Errorf("expected legacyEFIInaccessible=true on EIO error, got false")
	}

	outcome, _ := planLimineLayout(st)
	if outcome != limineLayoutUnreadable {
		t.Errorf("planLimineLayout = %d, want limineLayoutUnreadable (%d)", outcome, limineLayoutUnreadable)
	}

	res := reconcileLimineLayout(true)
	if res.status != recWarn {
		t.Errorf("reconcileLimineLayout = %d, want recWarn (%d)", res.status, recWarn)
	}
	if !strings.Contains(res.detail, "cannot inspect limine bootloader binaries under /boot") {
		t.Errorf("expected warning mentioning bootloader binaries, got: %s", res.detail)
	}
	if res.remedy != "sudo ryoku doctor --check" {
		t.Errorf("expected remedy 'sudo ryoku doctor --check', got %q", res.remedy)
	}
}

// TestPlanLimineLayoutInaccessibleEFIWithMissingConfigsNotSkipped verifies that
// an inaccessible EFI binary with genuinely absent configs produces limineLayoutUnreadable,
// NOT limineLayoutSkip.
func TestPlanLimineLayoutInaccessibleEFIWithMissingConfigsNotSkipped(t *testing.T) {
	stTool := limineLayoutState{
		limineInstalled:     true,
		espConfExists:       false,
		shadowExists:        false,
		toolEFIInaccessible: true,
	}
	outcome, _ := planLimineLayout(stTool)
	if outcome != limineLayoutUnreadable {
		t.Fatalf("outcome = %d, want limineLayoutUnreadable (%d); inaccessible tool EFI must not skip even when configs are absent", outcome, limineLayoutUnreadable)
	}

	stLegacy := limineLayoutState{
		limineInstalled:       true,
		espConfExists:         false,
		shadowExists:          false,
		legacyEFIInaccessible: true,
	}
	outcome, _ = planLimineLayout(stLegacy)
	if outcome != limineLayoutUnreadable {
		t.Fatalf("outcome = %d, want limineLayoutUnreadable (%d); inaccessible legacy EFI must not skip even when configs are absent", outcome, limineLayoutUnreadable)
	}
}

// TestReconcileLimineDefaultsUnreadable verifies that when /etc/default/limine is
// unreadable (e.g. permission denied), dependent checks (reconcileLimineUKITree and
// reconcileLimineOSName) warn instead of silently assuming the file or settings are absent.
func TestReconcileLimineDefaultsUnreadable(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("skipping DAC permission-denied test when running as root (root bypasses DAC permissions)")
	}
	dir := t.TempDir()
	stubLimineBootGates(t)

	origESP, origPkg, origDef := limineESPConf, liminePkgInstalled, limineDefaultsPath
	t.Cleanup(func() {
		limineESPConf, liminePkgInstalled, limineDefaultsPath = origESP, origPkg, origDef
	})
	liminePkgInstalled = func(string) bool { return true }

	// Create unreadable defaults file (mode 0000)
	unreadableDef := filepath.Join(dir, "default_limine")
	if err := os.WriteFile(unreadableDef, []byte("ENABLE_UKI=yes\nTARGET_OS_NAME=\"Ryoku\"\n"), 0o000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(unreadableDef, 0o600) })
	limineDefaultsPath = unreadableDef

	// Readable esp config
	readableESP := filepath.Join(dir, "limine.conf")
	if err := os.WriteFile(readableESP, []byte("timeout: 3\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	limineESPConf = readableESP

	// reconcileLimineUKITree must warn about unreadable defaults, NOT return okRes
	resUKI := reconcileLimineUKITree(true)
	if resUKI.status != recWarn {
		t.Errorf("reconcileLimineUKITree on unreadable defaults: got status %d, want recWarn (%d)", resUKI.status, recWarn)
	}
	if !strings.Contains(resUKI.detail, "cannot read") || !strings.Contains(resUKI.detail, unreadableDef) {
		t.Errorf("unexpected detail: %s", resUKI.detail)
	}
	if resUKI.remedy != "sudo ryoku doctor --check" {
		t.Errorf("expected remedy 'sudo ryoku doctor --check', got %q", resUKI.remedy)
	}

	// reconcileLimineOSName must warn about unreadable defaults, NOT return okRes
	resOS := reconcileLimineOSName(true)
	if resOS.status != recWarn {
		t.Errorf("reconcileLimineOSName on unreadable defaults: got status %d, want recWarn (%d)", resOS.status, recWarn)
	}
	if !strings.Contains(resOS.detail, "cannot read") || !strings.Contains(resOS.detail, unreadableDef) {
		t.Errorf("unexpected detail: %s", resOS.detail)
	}
	if resOS.remedy != "sudo ryoku doctor --check" {
		t.Errorf("expected remedy 'sudo ryoku doctor --check', got %q", resOS.remedy)
	}
}
