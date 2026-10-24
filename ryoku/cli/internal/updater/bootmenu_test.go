package updater

import (
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"
)

// mountinfo as a Fedora install with a separate /boot and the kickstart's
// root, home and snapshots subvolumes shows it.
const fedoraMountInfo = `43 1 0:35 /root / rw,relatime shared:1 - btrfs /dev/mapper/luks-1 rw,seclabel,compress=zstd:1,subvol=/root
61 43 0:35 /home /home rw,relatime shared:2 - btrfs /dev/mapper/luks-1 rw,seclabel,subvol=/home
62 43 0:35 /snapshots /.snapshots rw,relatime shared:3 - btrfs /dev/mapper/luks-1 rw,seclabel,subvol=/snapshots
73 43 259:2 / /boot rw,relatime shared:167 - ext4 /dev/vda2 rw,seclabel
`

func TestParseMountInfoReadsSubvolumes(t *testing.T) {
	m := parseMountInfo(fedoraMountInfo)
	if got := m["/"]; got.root != "/root" || got.fstype != "btrfs" || got.source != "/dev/mapper/luks-1" {
		t.Fatalf("root mount = %+v", got)
	}
	if got := m["/.snapshots"].root; got != "/snapshots" {
		t.Fatalf("snapshots subvolume = %q", got)
	}
	if got := m["/boot"]; got.fstype != "ext4" || got.source != "/dev/vda2" {
		t.Fatalf("boot mount = %+v", got)
	}
}

func TestEntryOptionsSwapTheSubvolumeOnly(t *testing.T) {
	opts, flags := baseSnapshotOptions("BOOT_IMAGE=(hd0,gpt2)/vmlinuz-6.17 root=UUID=abc ro rootflags=subvol=root,compress=zstd:1 rd.luks.uuid=luks-1 rhgb quiet systemd.unit=multi-user.target rd.ryoku.preview=x")
	if opts != "root=UUID=abc rd.luks.uuid=luks-1 rhgb quiet" {
		t.Fatalf("base options = %q", opts)
	}
	if !reflect.DeepEqual(flags, []string{"compress=zstd:1"}) {
		t.Fatalf("rootflags kept = %q", flags)
	}
	l := menuLayout{options: opts, rootflags: flags}
	got := l.entryOptions("snapshots/42/snapshot", "rd.ryoku.preview=snapshots/42/snapshot")
	want := "root=UUID=abc rd.luks.uuid=luks-1 rhgb quiet ro rootflags=subvol=snapshots/42/snapshot,compress=zstd:1 rd.ryoku.preview=snapshots/42/snapshot"
	if got != want {
		t.Fatalf("entry options\n got %q\nwant %q", got, want)
	}
}

func TestCompareVersionsOrdersFedoraKernels(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"6.17.1-300.fc44.x86_64", "6.9.12-200.fc44.x86_64", 1},
		{"6.17.1-300.fc44.x86_64", "6.17.10-300.fc44.x86_64", -1},
		{"6.17.1-300.fc44.x86_64", "6.17.1-300.fc44.x86_64", 0},
		{"6.17.1-301.fc44.x86_64", "6.17.1-300.fc44.x86_64", 1},
	}
	for _, c := range cases {
		got := compareVersions(c.a, c.b)
		if (got > 0) != (c.want > 0) || (got < 0) != (c.want < 0) {
			t.Errorf("compareVersions(%q, %q) = %d, want sign of %d", c.a, c.b, got, c.want)
		}
	}
}

func writeSnapshot(t *testing.T, dir, num, kind, desc string, kvers ...string) {
	t.Helper()
	base := filepath.Join(dir, num)
	for _, k := range kvers {
		mod := filepath.Join(base, "snapshot/usr/lib/modules", k)
		if err := os.MkdirAll(mod, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(mod, "vmlinuz"), []byte("kernel"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	info := `<?xml version="1.0"?>
<snapshot>
  <type>` + kind + `</type>
  <num>` + num + `</num>
  <date>2026-09-20 10:11:12</date>
  <description>` + desc + `</description>
  <cleanup>number</cleanup>
</snapshot>
`
	if err := os.MkdirAll(base, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(base, "info.xml"), []byte(info), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestSnapshotLabelSaysWhenNotSnapperType(t *testing.T) {
	for _, tc := range []struct{ kind, desc, want string }{
		{"single", "vm test snapshot", "Snapshot 7, 2026-10-16 19:39 UTC, vm test snapshot"},
		{"pre", "dnf transaction", "Snapshot 7, 2026-10-16 19:39 UTC, before dnf transaction"},
		{"post", "dnf transaction", "Snapshot 7, 2026-10-16 19:39 UTC, after dnf transaction"},
		{"single", "", "Snapshot 7, 2026-10-16 19:39 UTC"},
	} {
		got := snapshotLabel(bootSnapshot{Num: "7", Kind: tc.kind, Date: "2026-10-16 19:39:20", Description: tc.desc})
		if got != tc.want {
			t.Errorf("%s %q: label = %q, want %q", tc.kind, tc.desc, got, tc.want)
		}
	}
}

func TestReadBootSnapshotsNewestFirstWithTheirKernel(t *testing.T) {
	dir := t.TempDir()
	writeSnapshot(t, dir, "9", "pre", "ryoku update", "6.16.9-200.fc44.x86_64")
	writeSnapshot(t, dir, "10", "post", "ryoku update", "6.16.9-200.fc44.x86_64", "6.17.1-300.fc44.x86_64")
	writeSnapshot(t, dir, "11", "single", "no kernel")
	if err := os.MkdirAll(filepath.Join(dir, "12"), 0o755); err != nil {
		t.Fatal(err)
	}
	snaps := readBootSnapshots(dir)
	var got []string
	for _, s := range snaps {
		got = append(got, s.Num+"="+s.kver)
	}
	want := []string{"11=", "10=6.17.1-300.fc44.x86_64", "9=6.16.9-200.fc44.x86_64"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("snapshots = %q, want %q", got, want)
	}
	if snaps[1].Kind != "post" || snaps[1].Description != "ryoku update" || snaps[1].Date != "2026-09-20 10:11:12" {
		t.Fatalf("info.xml not read: %+v", snaps[1])
	}
}

func TestRenderSnapshotMenu(t *testing.T) {
	l := menuLayout{bootUUID: "b00t", options: "root=UUID=abc rhgb quiet", rootSubvol: "root", snapSubvol: ".snapshots"}
	snaps := []bootSnapshot{{Num: "42", Kind: "pre", Date: "2026-09-20 10:11:12", Description: "it's ryoku update", kver: "6.17.1-300.fc44.x86_64"}}
	cfg := renderSnapshotMenu(snaps, l)
	for _, want := range []string{
		"submenu 'Ryoku snapshots' --id ryoku-snapshots {\n",
		"  menuentry 'Snapshot 42, 2026-09-20 10:11 UTC, before its ryoku update' --id ryoku-snapshot-42 {\n",
		"    search --no-floppy --fs-uuid --set=root b00t\n",
		"    linux /ryoku/snapshots/6.17.1-300.fc44.x86_64/vmlinuz root=UUID=abc rhgb quiet ro rootflags=subvol=.snapshots/42/snapshot rd.ryoku.preview=.snapshots/42/snapshot\n",
		"    initrd /ryoku/snapshots/6.17.1-300.fc44.x86_64/initramfs.img\n",
	} {
		if !strings.Contains(cfg, want) {
			t.Errorf("menu lacks %q\n%s", want, cfg)
		}
	}
	if strings.Contains(cfg, "restore") {
		t.Fatalf("a snapshot restores from the menu instead of from its look boot:\n%s", cfg)
	}
	if got := strings.Count(cfg, "{"); got != strings.Count(cfg, "}") {
		t.Fatalf("unbalanced braces in\n%s", cfg)
	}
	if empty := renderSnapshotMenu(nil, l); strings.Contains(empty, "submenu") {
		t.Fatalf("an empty menu still opens a submenu:\n%s", empty)
	}
}

func TestSnapshotEntryIDIsTheGrubRebootPath(t *testing.T) {
	if got := snapshotEntryID("42"); got != "ryoku-snapshots>ryoku-snapshot-42" {
		t.Fatalf("entry id = %q", got)
	}
	cfg := renderSnapshotMenu([]bootSnapshot{{Num: "42", kver: "k"}}, menuLayout{})
	if id := strings.TrimPrefix(snapshotEntryID("42"), snapshotMenuID+">"); !strings.Contains(cfg, " --id "+id+" ") {
		t.Errorf("menu has no entry %s", id)
	}
}

func TestRestoredEntryBootsTheRootWithTheLookKernel(t *testing.T) {
	opts, flags := baseSnapshotOptions("BOOT_IMAGE=/ryoku/snapshots/6.17.1/vmlinuz root=UUID=abc rhgb quiet ro rootflags=subvol=.snapshots/42/snapshot,compress=zstd:1 rd.ryoku.preview=.snapshots/42/snapshot")
	entry := renderRestoredEntry(menuLayout{bootUUID: "b00t", options: opts, rootflags: flags}, "root", "6.17.1")
	for _, want := range []string{
		"menuentry 'Ryoku: restored system' --id ryoku-restored {\n",
		"  linux /ryoku/snapshots/6.17.1/vmlinuz root=UUID=abc rhgb quiet ro rootflags=subvol=root,compress=zstd:1\n",
		"  initrd /ryoku/snapshots/6.17.1/initramfs.img\n",
	} {
		if !strings.Contains(entry, want) {
			t.Errorf("restored entry lacks %q\n%s", want, entry)
		}
	}
	if strings.Contains(entry, "rd.ryoku.") {
		t.Fatalf("the restored root boots as a look boot again:\n%s", entry)
	}
}

func TestRestoreReadsTheLookBootAndTheRootSubvolume(t *testing.T) {
	cmdline := "BOOT_IMAGE=/x root=UUID=abc ro rootflags=subvol=.snapshots/42/snapshot rd.ryoku.preview=.snapshots/42/snapshot quiet"
	if got := cmdlineValue(cmdline, "rd.ryoku.preview"); got != ".snapshots/42/snapshot" {
		t.Fatalf("preview = %q", got)
	}
	if got := cmdlineValue(cmdline, "rd.ryoku.restore"); got != "" {
		t.Fatalf("absent key = %q", got)
	}
	fstab := "#UUID=abc / btrfs subvol=old 0 0\nUUID=abc / btrfs subvol=root,compress=zstd:1 0 0\nUUID=abc /home btrfs subvol=home 0 0\n"
	if got := fstabRootSubvol(fstab); got != "root" {
		t.Fatalf("root subvolume = %q", got)
	}
	for path, want := range map[string]bool{
		".snapshots/42/snapshot": true,
		"root":                   true,
		"/root":                  false,
		"../root":                false,
		"root;reboot":            false,
		"":                       false,
	} {
		if got := safeSubvolPath(path); got != want {
			t.Errorf("safeSubvolPath(%q) = %v, want %v", path, got, want)
		}
	}
}

func TestBLSKernelsReadTheVersionWhateverTheToken(t *testing.T) {
	dir := t.TempDir()
	entries := map[string]string{
		"0879-7.2.9-201.fc44.x86_64.conf":       "7.2.9-201.fc44.x86_64",
		"b208-6.19.10-300.fc44.x86_64.conf":     "6.19.10-300.fc44.x86_64",
		"0879-7.2.9-201.fc44.x86_64~debug.conf": "7.2.9-201.fc44.x86_64+debug",
		"0879-0-rescue-0879.conf":               "0-rescue-0879",
	}
	for name, version := range entries {
		body := "title Fedora Linux\nversion " + version + "\nlinux /vmlinuz\n"
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got := blsKernels(dir)
	want := map[string]string{
		"7.2.9-201.fc44.x86_64":   "0879-7.2.9-201.fc44.x86_64",
		"6.19.10-300.fc44.x86_64": "b208-6.19.10-300.fc44.x86_64",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("kernels = %v, want %v", got, want)
	}
}

func TestSnapshotsListedNeedsAKernelCopy(t *testing.T) {
	old := bootDir
	bootDir = t.TempDir()
	defer func() { bootDir = old }()
	if snapshotsListed() {
		t.Fatal("listed with no kernel copies")
	}
	dir := filepath.Join(snapshotKernelDir(), "6.17.1-300.fc44.x86_64")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if snapshotsListed() {
		t.Fatal("listed with an empty kernel directory")
	}
	if err := os.WriteFile(filepath.Join(dir, "initramfs.img"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if !snapshotsListed() {
		t.Fatal("not listed with a kernel copy")
	}
}

func TestMenuFindsKernelCopiesInABootSubvolume(t *testing.T) {
	cloud := parseMountInfo(`43 1 0:35 /root / rw - btrfs /dev/vda3 rw,subvol=/root
50 43 0:35 /boot /boot rw - btrfs /dev/vda3 rw,subvol=/boot
`)
	if got := grubBootPrefix(cloud["/boot"]); got != "/boot" {
		t.Fatalf("prefix for a /boot subvolume = %q", got)
	}
	if got := grubBootPrefix(parseMountInfo(fedoraMountInfo)["/boot"]); got != "" {
		t.Fatalf("prefix for a /boot partition = %q", got)
	}
	l := menuLayout{bootUUID: "b00t", bootPrefix: "/boot", options: "root=UUID=abc", snapSubvol: ".snapshots"}
	cfg := renderSnapshotMenu([]bootSnapshot{{Num: "7", kver: "k"}}, l)
	for _, want := range []string{
		"    linux /boot/ryoku/snapshots/k/vmlinuz ",
		"    initrd /boot/ryoku/snapshots/k/initramfs.img\n",
	} {
		if !strings.Contains(cfg, want) {
			t.Errorf("menu lacks %q\n%s", want, cfg)
		}
	}
}

func TestExpiredBrokenRootsKeepTheNewestAndTheRecent(t *testing.T) {
	list := "ID 256 gen 90 top level 5 path root\n" +
		"ID 257 gen 90 top level 5 path .snapshots\n" +
		"ID 300 gen 40 top level 5 path <FS_TREE>/root.broken-20260901-100000\n" +
		"ID 301 gen 50 top level 5 path root.broken-20260910-100000\n" +
		"ID 302 gen 60 top level 5 path root.broken-20261010-100000\n" +
		"ID 303 gen 70 top level 5 path root.broken-20261015-100000\n" +
		"ID 304 gen 70 top level 256 path root/var/lib/root.broken-20260101-000000\n"
	now := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	got := expiredBrokenRoots(list, "root", now)
	want := []string{"root.broken-20260901-100000", "root.broken-20260910-100000"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("expired = %q, want %q", got, want)
	}
	only := "ID 300 gen 40 top level 5 path root.broken-20250101-000000\n"
	if got := expiredBrokenRoots(only, "root", now); len(got) != 0 {
		t.Fatalf("the only set-aside root was due: %q", got)
	}
}

func TestDracutFingerprintFollowsContentsNotTimes(t *testing.T) {
	dir := t.TempDir()
	hook := filepath.Join(dir, "hook.sh")
	if err := os.WriteFile(hook, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	before := dracutFingerprint([]string{dir, filepath.Join(dir, "missing")})
	old := time.Now().Add(-time.Hour)
	_ = os.Chtimes(hook, old, old)
	if got := dracutFingerprint([]string{dir, filepath.Join(dir, "missing")}); got != before {
		t.Fatal("a changed mtime changed the fingerprint")
	}
	if err := os.WriteFile(hook, []byte("new"), 0o644); err != nil {
		t.Fatal(err)
	}
	_ = os.Chtimes(hook, old, old)
	if got := dracutFingerprint([]string{dir}); got == before {
		t.Fatal("new contents with an old mtime kept the fingerprint")
	}
}

func TestProcStartTimeReadsThisProcess(t *testing.T) {
	start := procStartTime(os.Getpid())
	if _, err := strconv.ParseUint(start, 10, 64); err != nil {
		t.Fatalf("start time = %q, want clock ticks", start)
	}
	if got := procStartTime(-1); got != "" {
		t.Fatalf("a missing process gave %q", got)
	}
}
