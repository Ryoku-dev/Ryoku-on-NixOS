package doctor

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ryoku-cli/internal/host"
	"ryoku-cli/internal/sys"
	"ryoku-cli/internal/updater"
)

func stubDoctorDNF(t *testing.T) {
	t.Helper()
	oldManager := doctorPackageManager
	oldFilteredDNS := doctorFilteredRyokuDNS
	doctorPackageManager = func() (host.PackageManager, error) { return host.DNF, nil }
	doctorFilteredRyokuDNS = func(string) bool { return false }
	t.Setenv("RYOKU_HOST_PKGMGR", "dnf")
	t.Cleanup(func() {
		doctorPackageManager = oldManager
		doctorFilteredRyokuDNS = oldFilteredDNS
	})
}

func assertNoForeignPackageAdvice(t *testing.T, result recResult) {
	t.Helper()
	text := strings.ToLower(result.detail + " " + result.remedy)
	for _, forbidden := range []string{"pacman", "aur", "limine", "xbps"} {
		if strings.Contains(text, forbidden) {
			t.Errorf("Fedora result mentions %q: %+v", forbidden, result)
		}
	}
}

func TestFedoraSnapperPlanCreatesTheLayoutOnBtrfs(t *testing.T) {
	outcome, _ := planSnapper(snapperState{manager: host.DNF, rootIsBtrfs: true, snapperInstalled: true})
	if outcome != snapperCreate {
		t.Fatalf("outcome = %v, want snapperCreate", outcome)
	}
}

func TestFedoraSnapperProblemsNameSysconfigAndNoForeignTools(t *testing.T) {
	outcome, problems := planSnapper(snapperState{
		manager: host.DNF, rootIsBtrfs: true, configExists: true, snapperInstalled: true,
		snapshotsExists: true, snapshotsIsSubvol: true, snapshotsMode: 0o750,
		confdExists: true, confdContents: `SNAPPER_CONFIGS=""`,
	})
	if outcome != snapperWarnInconsistent || len(problems) != 1 {
		t.Fatalf("outcome = %v, problems = %q", outcome, problems)
	}
	if !strings.Contains(problems[0], "/etc/sysconfig/snapper") {
		t.Fatalf("problem = %q, want the Fedora sysconfig path", problems[0])
	}
	assertNoForeignPackageAdvice(t, recResult{detail: strings.Join(problems, "; ")})
}

func TestFedoraSnapperPlanMovesANestedSnapshotsSubvolume(t *testing.T) {
	outcome, _ := planSnapper(snapperState{
		manager: host.DNF, rootIsBtrfs: true, configExists: true, snapperInstalled: true,
		snapshotsExists: true, snapshotsIsSubvol: true, snapshotsNested: true, snapshotsMode: 0o750,
	})
	if outcome != snapperMoveSnapshots {
		t.Fatalf("outcome = %v, want snapperMoveSnapshots", outcome)
	}
}

func TestFedoraSnapperFlagsSnapshotsMountedFromInsideTheRoot(t *testing.T) {
	outcome, problems := planSnapper(snapperState{
		manager: host.DNF, rootIsBtrfs: true, configExists: true, snapperInstalled: true,
		snapshotsExists: true, snapshotsIsSubvol: true, snapshotsMountedInRoot: true, snapshotsMode: 0o750,
	})
	if outcome != snapperWarnInconsistent || len(problems) != 1 || !strings.Contains(problems[0], "inside the root") {
		t.Fatalf("outcome = %v, problems = %q", outcome, problems)
	}
}

func TestInsideSubvol(t *testing.T) {
	for _, c := range []struct {
		sub, parent string
		want        bool
	}{
		{"/root/.snapshots", "/root", true},
		{"/.snapshots", "/root", false},
		{"/rootfs/.snapshots", "/root", false},
		{"/.snapshots", "/", false},
		{"/.snapshots", "", false},
	} {
		if got := insideSubvol(c.sub, c.parent); got != c.want {
			t.Errorf("insideSubvol(%q, %q) = %v, want %v", c.sub, c.parent, got, c.want)
		}
	}
}

func TestSnapshotsFstabLineFollowsTheRootEntry(t *testing.T) {
	fstab := "# comment\n" +
		"UUID=ab / btrfs subvol=root,compress=zstd:1,x-systemd.device-timeout=0 0 0\n" +
		"UUID=cd /boot ext4 defaults 1 2\n"
	want := "UUID=ab /.snapshots btrfs subvol=.snapshots,compress=zstd:1,x-systemd.device-timeout=0 0 0"
	if got := snapshotsFstabLine(fstab); got != want {
		t.Fatalf("line = %q, want %q", got, want)
	}
	if got := snapshotsFstabLine("UUID=ab / btrfs subvolid=256,compress=zstd:1 0 0\n"); got != "" {
		t.Fatalf("root without subvol= gave %q, want none", got)
	}
	if got := snapshotsFstabLine("UUID=ab / ext4 defaults 1 1\n"); got != "" {
		t.Fatalf("ext4 root gave %q, want none", got)
	}
}

func TestFstabMountsIgnoresComments(t *testing.T) {
	fstab := "#UUID=ab /.snapshots btrfs subvol=.snapshots 0 0\nUUID=ab / btrfs subvol=root 0 0\n"
	if fstabMounts(fstab, "/.snapshots") {
		t.Fatal("a commented entry counted as a mount")
	}
	if !fstabMounts(fstab, "/") {
		t.Fatal("the root entry was not found")
	}
}

func TestFedoraManifestUsesNativePackageLane(t *testing.T) {
	plan := updater.Plan{
		Install: []string{"base-package"},
		AUR:     []string{"community-tool"},
	}
	got := planSummary(host.DNF, &plan)
	if got != "install base-package, community-tool" {
		t.Fatalf("manifest plan = %q", got)
	}
}

func TestFedoraManifestSkipsUnavailableNativePackages(t *testing.T) {
	oldAvailability := doctorPackageAvailability
	doctorPackageAvailability = func(pkg string) int {
		if pkg == "blesh" || pkg == "songrec" {
			return host.ExitNotProvided
		}
		return host.ExitOK
	}
	t.Cleanup(func() { doctorPackageAvailability = oldAvailability })

	supported, unavailable := supportedManifestPackages(host.DNF, []string{"blesh", "quickshell", "songrec"})
	if got := strings.Join(supported, ","); got != "quickshell" {
		t.Fatalf("supported packages = %q", got)
	}
	if got := strings.Join(unavailable, ","); got != "blesh,songrec" {
		t.Fatalf("unavailable packages = %q", got)
	}
}

func TestFedoraPackageChannelReadsRPMRepo(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled := doctorPackageInstalled
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	t.Cleanup(func() { doctorPackageInstalled = oldInstalled })

	path := t.TempDir() + "/ryoku.repo"
	t.Setenv("RYOKU_DNF_REPO_CONFIG", path)
	if err := writeTestFile(path, dnfRepoConfig("stable")); err != nil {
		t.Fatal(err)
	}

	result := reconcileRyokuChannel(true)
	if result.status != recOK || !strings.Contains(result.detail, "stable packages") {
		t.Fatalf("channel result = %+v", result)
	}
	assertNoForeignPackageAdvice(t, result)
}

func TestFedoraPackageChannelRestoresSignedStableRepo(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled, oldKey := doctorPackageInstalled, dnfRepoKeyPresent
	oldWrite, oldRefresh := writeDNFRepoConfig, refreshDNFRepoMetadata
	oldIntent := sys.ChannelIntentFile
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	dnfRepoKeyPresent = func() bool { return true }
	sys.ChannelIntentFile = filepath.Join(t.TempDir(), "channel-intent")
	t.Cleanup(func() {
		doctorPackageInstalled, dnfRepoKeyPresent = oldInstalled, oldKey
		writeDNFRepoConfig, refreshDNFRepoMetadata = oldWrite, oldRefresh
		sys.ChannelIntentFile = oldIntent
	})

	path := t.TempDir() + "/ryoku.repo"
	t.Setenv("RYOKU_DNF_REPO_CONFIG", path)
	t.Setenv("RYOKU_RELEASE_BASE", "https://repo.example")
	var gotPath, gotConfig string
	refreshed := false
	writeDNFRepoConfig = func(path, contents string) error {
		gotPath, gotConfig = path, contents
		return nil
	}
	refreshDNFRepoMetadata = func() error {
		refreshed = true
		return nil
	}

	result := reconcileRyokuChannel(false)
	if result.status != recFixed || !refreshed {
		t.Fatalf("channel repair result = %+v refreshed=%v", result, refreshed)
	}
	const wantConfig = "[ryoku]\nname=Ryoku\nbaseurl=https://repo.example/x86_64\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-ryoku\n"
	if gotPath != path || gotConfig != wantConfig {
		t.Fatalf("repo config = path %q body %q", gotPath, gotConfig)
	}
	assertNoForeignPackageAdvice(t, result)
}

func TestFedoraMetadataQueryAcceptsRepositoryKeys(t *testing.T) {
	argsPath := t.TempDir() + "/dnf-args"
	t.Setenv("DNF_ARGS", argsPath)
	script := `printf '%s\n' "$@" > "$DNF_ARGS"; echo ryoku-desktop`
	stubPath(t, map[string]string{"dnf": script, "dnf5": script})

	if _, err := checkDNFRepoMetadata(); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	const want = "repoquery\n-y\n--repo=ryoku\n--available\nryoku-desktop\n"
	if string(raw) != want {
		t.Fatalf("dnf metadata args = %q, want %q", raw, want)
	}
}

func TestFedoraMetadataRefreshAcceptsRepositoryKeys(t *testing.T) {
	argsPath := t.TempDir() + "/sudo-args"
	t.Setenv("DNF_ARGS", argsPath)
	stubPath(t, map[string]string{
		"dnf5": ":",
		"sudo": `printf '%s\n' "$@" > "$DNF_ARGS"`,
	})

	if err := refreshDNFRepoMetadata(); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	const want = "dnf5\nmakecache\n-y\n--refresh\n--repo=ryoku\n"
	if string(raw) != want {
		t.Fatalf("dnf metadata refresh args = %q, want %q", raw, want)
	}
}

func TestFedoraPackageDatabaseRefreshesBrokenMetadata(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled := doctorPackageInstalled
	oldCheck, oldRefresh := checkDNFRepoMetadata, refreshDNFRepoMetadata
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	t.Cleanup(func() {
		doctorPackageInstalled = oldInstalled
		checkDNFRepoMetadata, refreshDNFRepoMetadata = oldCheck, oldRefresh
	})

	path := t.TempDir() + "/ryoku.repo"
	t.Setenv("RYOKU_DNF_REPO_CONFIG", path)
	if err := writeTestFile(path, dnfRepoConfig("stable")); err != nil {
		t.Fatal(err)
	}

	healthy := false
	checkDNFRepoMetadata = func() (string, error) {
		if healthy {
			return "ryoku-desktop", nil
		}
		return "repository metadata is unavailable", errors.New("metadata load failed")
	}
	refreshDNFRepoMetadata = func() error {
		healthy = true
		return nil
	}

	check := reconcileRyokuSyncDB(true)
	if check.status != recWouldFix || !strings.Contains(check.remedy, "makecache -y --refresh --repo=ryoku") {
		t.Fatalf("check result = %+v", check)
	}
	assertNoForeignPackageAdvice(t, check)

	applied := reconcileRyokuSyncDB(false)
	if applied.status != recFixed || !healthy {
		t.Fatalf("apply result = %+v healthy=%v", applied, healthy)
	}
	assertNoForeignPackageAdvice(t, applied)
}

func TestFedoraPackageDatabaseReportsRefreshFailure(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled := doctorPackageInstalled
	oldCheck, oldRefresh := checkDNFRepoMetadata, refreshDNFRepoMetadata
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	checkDNFRepoMetadata = func() (string, error) {
		return "repository metadata is unavailable", errors.New("metadata load failed")
	}
	refreshDNFRepoMetadata = func() error { return errors.New("network unavailable") }
	t.Cleanup(func() {
		doctorPackageInstalled = oldInstalled
		checkDNFRepoMetadata, refreshDNFRepoMetadata = oldCheck, oldRefresh
	})

	path := t.TempDir() + "/ryoku.repo"
	t.Setenv("RYOKU_DNF_REPO_CONFIG", path)
	if err := writeTestFile(path, dnfRepoConfig("stable")); err != nil {
		t.Fatal(err)
	}

	result := reconcileRyokuSyncDB(false)
	if result.status != recFailed || !strings.Contains(result.detail, "network unavailable") ||
		!strings.Contains(result.remedy, "makecache -y --refresh --repo=ryoku") {
		t.Fatalf("refresh failure result = %+v", result)
	}
	assertNoForeignPackageAdvice(t, result)
}

func TestFedoraPackageDatabaseReportsFilteredDNS(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled := doctorPackageInstalled
	oldCheck := checkDNFRepoMetadata
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	checkDNFRepoMetadata = func() (string, error) {
		return "repository metadata is unavailable", errors.New("TLS connection failed")
	}
	doctorFilteredRyokuDNS = func(repository string) bool {
		return strings.Contains(repository, "repo.ryoku.dev")
	}
	t.Cleanup(func() {
		doctorPackageInstalled = oldInstalled
		checkDNFRepoMetadata = oldCheck
	})

	path := t.TempDir() + "/ryoku.repo"
	t.Setenv("RYOKU_DNF_REPO_CONFIG", path)
	if err := writeTestFile(path, dnfRepoConfig("stable")); err != nil {
		t.Fatal(err)
	}

	result := reconcileRyokuSyncDB(true)
	if result.status != recFailed || !strings.Contains(result.detail, "DNS for ryoku.dev is being filtered") ||
		!strings.Contains(result.detail, "docs/updates.md#filtered-dns") {
		t.Fatalf("filtered DNS result = %+v", result)
	}
}

func TestFedoraBootGuardUsesSystemdUnit(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled := doctorPackageInstalled
	oldCheckout, oldShipped := bootGuardCheckout, bootGuardShipped
	oldWritable, oldService := bootGuardWritable, doctorService
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	bootGuardCheckout = func() bool { return false }
	bootGuardShipped = func(manager host.PackageManager) bool { return manager == host.DNF }
	bootGuardWritable = func() bool { return false }
	doctorService = func(args ...string) int { return host.ExitFalse }
	t.Cleanup(func() {
		doctorPackageInstalled = oldInstalled
		bootGuardCheckout, bootGuardShipped = oldCheckout, oldShipped
		bootGuardWritable, doctorService = oldWritable, oldService
	})

	result := reconcileBootGuard(true)
	if result.status != recWouldFix || !strings.Contains(result.remedy, "systemctl enable ryoku-boot-guard.service") {
		t.Fatalf("boot guard result = %+v", result)
	}
	assertNoForeignPackageAdvice(t, result)
}

func TestFedoraPendingConfigAndOrphanAdvice(t *testing.T) {
	stubDoctorDNF(t)
	oldFind, oldOrphans := doctorFindPendingConfig, doctorOrphans
	doctorFindPendingConfig = func(pattern string) []string {
		if pattern == "*.rpmnew" {
			return []string{"/etc/example.conf.rpmnew"}
		}
		return nil
	}
	doctorOrphans = func() ([]string, error) { return []string{"unused-package"}, nil }
	t.Cleanup(func() {
		doctorFindPendingConfig, doctorOrphans = oldFind, oldOrphans
	})

	pending := reconcilePacnew(true)
	if pending.status != recWarn || !strings.Contains(pending.detail, ".rpmnew") {
		t.Fatalf("pending result = %+v", pending)
	}
	assertNoForeignPackageAdvice(t, pending)

	orphans := reconcileOrphans(true)
	if orphans.status != recNote || !strings.Contains(orphans.remedy, "autoremove") {
		t.Fatalf("orphan result = %+v", orphans)
	}
	assertNoForeignPackageAdvice(t, orphans)
}

func TestFedoraNvidiaStaysOnNouveauWithManualRPMFusionAdvice(t *testing.T) {
	stubDoctorDNF(t)
	oldManager, oldPCI, oldModule := nvidiaPackageManager, nvidiaPCIOutput, nvidiaModuleDir
	nvidiaPackageManager = func() host.PackageManager { return host.DNF }
	nvidiaPCIOutput = func() string { return "NVIDIA Corporation AD107M" }
	nvidiaModuleDir = filepath.Join(t.TempDir(), "nvidia")
	t.Cleanup(func() {
		nvidiaPackageManager, nvidiaPCIOutput, nvidiaModuleDir = oldManager, oldPCI, oldModule
	})

	if pkg := nvidia580Package(); pkg != "akmod-nvidia" {
		t.Fatalf("Fedora NVIDIA package = %q", pkg)
	}
	result := reconcileNvidiaModeset(true)
	if result.status != recNote || !strings.Contains(result.detail, "Nouveau") ||
		!strings.Contains(result.remedy, "RPM Fusion") || !strings.Contains(result.remedy, "akmod-nvidia") ||
		!strings.Contains(result.remedy, "dracut --regenerate-all --force") {
		t.Fatalf("NVIDIA result = %+v", result)
	}
	assertNoForeignPackageAdvice(t, result)

	detail := nvidiaMissingModuleDetail(host.DNF)
	if !strings.Contains(detail, "keeps Nouveau active") ||
		strings.Contains(detail, "nvidia-open") || strings.Contains(detail, "mkinitcpio") || strings.Contains(detail, "pacman") {
		t.Fatalf("Fedora missing-module detail = %q", detail)
	}

	bin := t.TempDir()
	log := bin + "/sudo.log"
	if err := os.WriteFile(bin+"/sudo", []byte("#!/bin/sh\nprintf '%s\\n' \"$*\" >\"$NVIDIA_TEST_LOG\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NVIDIA_TEST_LOG", log)
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))
	if err := rebuildInitramfs(); err != nil {
		t.Fatalf("Fedora initramfs rebuild: %v", err)
	}
	body, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(string(body)); got != "dracut --regenerate-all --force" {
		t.Fatalf("Fedora initramfs command = %q", got)
	}
}

func TestFedoraBootReconcilersSkipWithoutForeignBootAdvice(t *testing.T) {
	stubDoctorDNF(t)
	for name, reconcile := range map[string]func(bool) recResult{
		"boot space":        reconcileBootSpace,
		"GPU image trim":    reconcileInitramfsGPUTrim,
		"console key image": reconcileInitramfsConsoleKeys,
		"boot menu":         reconcileLimineLayout,
	} {
		t.Run(name, func(t *testing.T) {
			result := reconcile(true)
			if result.status != recOK {
				t.Fatalf("result = %+v", result)
			}
			assertNoForeignPackageAdvice(t, result)
		})
	}
}

func TestFedoraShippedAppQueryAcceptsRepositoryKeys(t *testing.T) {
	stubDoctorDNF(t)
	argsPath := t.TempDir() + "/dnf-args"
	t.Setenv("DNF_ARGS", argsPath)
	script := `printf '%s\n' "$@" > "$DNF_ARGS"`
	stubPath(t, map[string]string{"dnf": script, "dnf5": script})

	if !appInstalledAsDep("example-app") {
		t.Fatal("an app absent from --userinstalled should be treated as automatic")
	}
	raw, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	const want = "repoquery\n-y\n--userinstalled\n--qf\n%{name}\n\nexample-app\n"
	if string(raw) != want {
		t.Fatalf("dnf repoquery args = %q, want %q", raw, want)
	}
}

func TestFedoraShippedAppQueryIgnoresDNF4BlankRows(t *testing.T) {
	stubDoctorDNF(t)
	script := `printf 'example-app\n\n'`
	stubPath(t, map[string]string{"dnf": script, "dnf5": script})

	if appInstalledAsDep("example-app") {
		t.Fatal("a user-installed app must not be classified as automatic")
	}
}

func TestFedoraShippedAppsSkipUnavailablePackages(t *testing.T) {
	stubDoctorDNF(t)
	isolateProvisioned(t)
	oldInstalled, oldDep := appInstalled, appInstalledAsDep
	oldInstall, oldExplicit := installShippedApps, markAppsExplicit
	oldAvailability := doctorPackageAvailability
	appInstalled = func(string) bool { return true }
	appInstalledAsDep = func(string) bool { return false }
	doctorPackageAvailability = func(pkg string) int {
		switch pkg {
		case "blesh", "waifu2x-ncnn-vulkan", "songrec":
			return host.ExitNotProvided
		default:
			return host.ExitOK
		}
	}
	installShippedApps = func(pkgs []string) { t.Fatalf("installed unavailable packages: %v", pkgs) }
	markAppsExplicit = func(pkgs []string) { t.Fatalf("changed ownership unexpectedly: %v", pkgs) }
	for _, app := range shippedApps() {
		recordProvisioned(app.pkg)
	}
	t.Cleanup(func() {
		appInstalled, appInstalledAsDep = oldInstalled, oldDep
		installShippedApps, markAppsExplicit = oldInstall, oldExplicit
		doctorPackageAvailability = oldAvailability
	})

	result := reconcileShippedApps(true)
	if result.status != recNote || strings.Contains(result.detail, "would install") {
		t.Fatalf("unavailable shipped-app result = %+v", result)
	}
	for _, pkg := range []string{"blesh", "waifu2x-ncnn-vulkan", "songrec"} {
		if !strings.Contains(result.detail, pkg) {
			t.Errorf("unavailable result does not name %s: %s", pkg, result.detail)
		}
	}
}

func TestFedoraShippedAndRetiredAppsUseNativePackageAdvice(t *testing.T) {
	stubDoctorDNF(t)
	isolateProvisioned(t)
	oldInstalled, oldDep := appInstalled, appInstalledAsDep
	oldInstall, oldExplicit := installShippedApps, markAppsExplicit
	oldAvailability := doctorPackageAvailability
	oldRetiredInstalled, oldRetiredRemove := retiredAppInstalled, removeRetiredApp
	appInstalled = func(string) bool { return false }
	appInstalledAsDep = func(string) bool { return false }
	doctorPackageAvailability = func(string) int { return host.ExitOK }
	installShippedApps = func(pkgs []string) { t.Fatalf("check mode installed %v", pkgs) }
	markAppsExplicit = func(pkgs []string) { t.Fatalf("check mode changed ownership of %v", pkgs) }
	retiredAppInstalled = func(pkg string) bool { return pkg == "ryomotion" }
	removeRetiredApp = func(string) error { t.Fatal("check mode removed a package"); return nil }
	t.Cleanup(func() {
		appInstalled, appInstalledAsDep = oldInstalled, oldDep
		installShippedApps, markAppsExplicit = oldInstall, oldExplicit
		doctorPackageAvailability = oldAvailability
		retiredAppInstalled, removeRetiredApp = oldRetiredInstalled, oldRetiredRemove
	})

	shipped := reconcileShippedApps(true)
	if shipped.status != recWouldFix || !strings.Contains(shipped.detail, "would install") {
		t.Fatalf("shipped apps result = %+v", shipped)
	}
	assertNoForeignPackageAdvice(t, shipped)

	retired := reconcileRetiredApps(true)
	if retired.status != recWouldFix || !strings.Contains(retired.remedy, "remove -y ryomotion") {
		t.Fatalf("retired app result = %+v", retired)
	}
	assertNoForeignPackageAdvice(t, retired)
}

func writeTestFile(path, body string) error {
	return os.WriteFile(path, []byte(body), 0o644)
}

func TestFedoraPackageChannelRestoresTheRecordedChannel(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled, oldKey := doctorPackageInstalled, dnfRepoKeyPresent
	oldWrite, oldRefresh := writeDNFRepoConfig, refreshDNFRepoMetadata
	oldIntent := sys.ChannelIntentFile
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	dnfRepoKeyPresent = func() bool { return true }
	sys.ChannelIntentFile = filepath.Join(t.TempDir(), "channel-intent")
	t.Cleanup(func() {
		doctorPackageInstalled, dnfRepoKeyPresent = oldInstalled, oldKey
		writeDNFRepoConfig, refreshDNFRepoMetadata = oldWrite, oldRefresh
		sys.ChannelIntentFile = oldIntent
	})
	if err := os.WriteFile(sys.ChannelIntentFile, []byte("testing\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_DNF_REPO_CONFIG", t.TempDir()+"/ryoku.repo")
	var gotConfig string
	writeDNFRepoConfig = func(_, contents string) error {
		gotConfig = contents
		return nil
	}
	refreshDNFRepoMetadata = func() error { return nil }

	if result := reconcileRyokuChannel(false); result.status != recFixed {
		t.Fatalf("channel repair result = %+v", result)
	}
	if !strings.Contains(gotConfig, "baseurl="+host.RepoURLFor(host.DNF, sys.ChannelTesting)+"\n") {
		t.Fatalf("a testing box was restored onto another channel: %q", gotConfig)
	}
}

func TestFedoraPackageChannelDoesNotRestoreARepoWithoutItsKey(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled, oldKey, oldWrite := doctorPackageInstalled, dnfRepoKeyPresent, writeDNFRepoConfig
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	dnfRepoKeyPresent = func() bool { return false }
	wrote := false
	writeDNFRepoConfig = func(string, string) error {
		wrote = true
		return nil
	}
	t.Cleanup(func() {
		doctorPackageInstalled, dnfRepoKeyPresent, writeDNFRepoConfig = oldInstalled, oldKey, oldWrite
	})
	t.Setenv("RYOKU_DNF_REPO_CONFIG", t.TempDir()+"/ryoku.repo")

	result := reconcileRyokuChannel(false)
	if wrote || result.status != recWarn || !strings.Contains(result.remedy, "installer") {
		t.Fatalf("restored a repository that names a missing key: %+v wrote=%v", result, wrote)
	}
}

func TestFedoraMetadataWithoutRyokuDesktopIsNotHealthy(t *testing.T) {
	stubPath(t, map[string]string{"dnf5": "echo 'Updating and loading repositories:'"})
	if _, err := checkDNFRepoMetadata(); !errors.Is(err, errDNFRepoEmpty) {
		t.Fatalf("an empty repository passed the metadata check: %v", err)
	}
}

func TestFedoraEmptyStableBeforeTheFirstReleaseIsANote(t *testing.T) {
	stubDoctorDNF(t)
	oldInstalled, oldCheck, oldStatus := doctorPackageInstalled, checkDNFRepoMetadata, doctorFedoraReleaseStatus
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	checkDNFRepoMetadata = func() (string, error) { return "", errDNFRepoEmpty }
	doctorFedoraReleaseStatus = func() (host.FedoraReleaseStatus, error) {
		return host.FedoraReleaseStatus{Version: "44", RepositoryChecked: true, Supported: []string{"44", "45"}, AwaitingFirstRelease: true}, nil
	}
	t.Cleanup(func() {
		doctorPackageInstalled, checkDNFRepoMetadata, doctorFedoraReleaseStatus = oldInstalled, oldCheck, oldStatus
	})
	path := t.TempDir() + "/ryoku.repo"
	t.Setenv("RYOKU_DNF_REPO_CONFIG", path)
	if err := writeTestFile(path, dnfRepoConfig("stable")); err != nil {
		t.Fatal(err)
	}

	result := reconcileRyokuSyncDB(false)
	if result.status != recNote || !strings.Contains(result.detail, "first Fedora release") {
		t.Fatalf("empty pre-release stable result = %+v", result)
	}
}

func TestFedoraNvidiaAdviceFollowsTheLoadedModule(t *testing.T) {
	stubDoctorDNF(t)
	oldManager, oldPCI, oldInstalled, oldModule := nvidiaPackageManager, nvidiaPCIOutput, nvidiaPackageInstalled, nvidiaModuleDir
	nvidiaPackageManager = func() host.PackageManager { return host.DNF }
	nvidiaPCIOutput = func() string { return "NVIDIA Corporation AD107M" }
	nvidiaPackageInstalled = func(name string) bool { return name == "akmod-nvidia" }
	nvidiaModuleDir = filepath.Join(t.TempDir(), "nvidia")
	t.Cleanup(func() {
		nvidiaPackageManager, nvidiaPCIOutput, nvidiaPackageInstalled, nvidiaModuleDir = oldManager, oldPCI, oldInstalled, oldModule
	})

	if result := reconcileNvidiaModeset(true); result.status != recNote || !strings.Contains(result.remedy, "dracut") {
		t.Fatalf("an installed but unloaded driver lost its setup advice: %+v", result)
	}
	if err := os.Mkdir(nvidiaModuleDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if result := reconcileNvidiaModeset(true); result.status != recOK || result.remedy != "" {
		t.Fatalf("a loaded proprietary driver was reported as Nouveau: %+v", result)
	}
}
