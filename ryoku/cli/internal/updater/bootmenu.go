package updater

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/xml"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// The snapshot boot menu makes snapper snapshots bootable from Fedora's GRUB
// without touching what Secure Boot verifies. Pieces (fedora/system/boot/):
//
//   - /etc/grub.d/15_ryoku_snapshots, rendered into grub.cfg once, sources
//     snapshotMenuCfg, which `ryoku boot-menu sync` rewrites after every
//     snapshot: ryoku-snapshot-menu.path starts ryoku-snapshot-menu.service
//     when /.snapshots changes, and the snapper plugin touches /.snapshots once
//     a snapshot is complete.
//   - GRUB cannot read the root filesystem on an encrypted install, so each
//     kernel version a snapshot needs gets a copy on /boot under
//     snapshotKernelDir: Fedora's signed vmlinuz, which shim and GRUB verify
//     like any other kernel, and an initramfs built with the ryoku-snapshot
//     dracut module.
//   - Each snapshot gets one entry, a look boot: the snapshot read-only with
//     its writes in RAM (rd.ryoku.preview). `ryoku boot-menu restore`, run in
//     that boot, makes it the root again, as limine-snapper-restore does on
//     Arch (bootmenu_restore.go).
const (
	snapshotMenuID    = "ryoku-snapshots"
	snapshotDracutMod = "ryoku-snapshot"
	// what a new kernel copy must leave free on /boot, so a Fedora kernel
	// update still fits after it.
	bootHeadroom = 300 << 20
)

// Paths the menu reads and writes, variables so tests can point them at a
// scratch tree.
var (
	bootDir         = "/boot"
	snapshotsDir    = "/.snapshots"
	modulesDir      = "/usr/lib/modules"
	blsDir          = "/boot/loader/entries"
	kernelCmdline   = "/etc/kernel/cmdline"
	procCmdline     = "/proc/cmdline"
	mountInfo       = "/proc/self/mountinfo"
	dracutModuleDir = "/usr/lib/dracut/modules.d/90ryoku-snapshot"
	// dracut itself, the other half of what a kernel copy's look boot runs.
	// Its configuration is left out: a copy built under an earlier one still
	// boots, and driver packages change it often.
	dracutVersionFile = "/usr/lib/dracut/dracut-version.sh"
)

func snapshotMenuCfg() string   { return filepath.Join(bootDir, "grub2", "ryoku-snapshots.cfg") }
func snapshotKernelDir() string { return filepath.Join(bootDir, "ryoku", "snapshots") }

// BootMenu is `ryoku boot-menu`, run as root by the snapshot units, and by the
// user (through sudo) for a restore from a look boot.
func BootMenu(args []string) error {
	if os.Geteuid() != 0 {
		return fmt.Errorf(i18n.T("ryoku boot-menu runs as root (sudo ryoku boot-menu %s)"), strings.Join(args, " "))
	}
	if len(args) == 1 {
		switch args[0] {
		case "sync":
			// the path unit fires as soon as snapper starts a snapshot, and
			// systemd does not restart a unit that is still running, so go again
			// until /.snapshots holds still.
			for {
				before := modTime(snapshotsDir)
				if err := syncSnapshotMenu(); err != nil {
					return err
				}
				if modTime(snapshotsDir).Equal(before) {
					return nil
				}
			}
		case "restore":
			return restoreSnapshot()
		case "restored":
			return snapshotRestored()
		}
	}
	return fmt.Errorf(i18n.T("usage: ryoku boot-menu sync|restore|restored"))
}

// bootSnapshot is one snapper snapshot as the menu shows it.
type bootSnapshot struct {
	Num         string `xml:"num"`
	Kind        string `xml:"type"`
	Date        string `xml:"date"`
	Description string `xml:"description"`
	kver        string
}

// menuLayout is what every entry shares: where /boot is for GRUB, the kernel
// options, and the btrfs subvolume names the cmdlines use.
type menuLayout struct {
	bootUUID string
	// bootPrefix is where /boot sits inside its filesystem as GRUB sees it:
	// "" for a /boot partition, the subvolume path for a /boot subvolume.
	bootPrefix string
	options    string
	rootflags  []string
	rootSubvol string
	snapSubvol string
}

func syncSnapshotMenu() error {
	layout, err := readMenuLayout()
	if err != nil {
		fmt.Println(i18n.T("boot menu:"), err)
		return nil
	}
	var listed []bootSnapshot
	used := map[string]bool{}
	inputs := sync.OnceValue(func() string {
		return dracutFingerprint([]string{dracutModuleDir, dracutVersionFile})
	})
	for _, s := range readBootSnapshots(snapshotsDir) {
		if s.kver == "" {
			continue
		}
		if err := ensureSnapshotKernel(s.kver, inputs); err != nil {
			fmt.Printf(i18n.T("boot menu: snapshot %s left out: %v\n"), s.Num, err)
			continue
		}
		used[s.kver] = true
		listed = append(listed, s)
	}
	if err := sys.WriteFileAtomic(snapshotMenuCfg(), renderSnapshotMenu(listed, layout), 0o644); err != nil {
		return err
	}
	pruneSnapshotKernels(used)
	pruneBrokenRoots(layout.rootSubvol)
	fmt.Printf(i18n.T("boot menu: %d snapshot(s) in the Ryoku snapshots menu\n"), len(listed))
	return nil
}

// readMenuLayout gathers the facts the entries need and refuses a layout the
// restore cannot serve: /boot must be its own filesystem (GRUB reads the
// kernel copies from it), and the snapshots must live outside the root
// subvolume, since a restore replaces that subvolume.
func readMenuLayout() (menuLayout, error) {
	var l menuLayout
	mounts := parseMountInfo(readText(mountInfo))
	boot, ok := mounts[bootDir]
	if !ok {
		return l, fmt.Errorf(i18n.T("/boot is not a separate filesystem; snapshots are not bootable"))
	}
	root, ok := mounts["/"]
	if !ok || root.fstype != "btrfs" {
		return l, fmt.Errorf(i18n.T("/ is not btrfs; no snapshots to boot"))
	}
	snaps, ok := mounts[snapshotsDir]
	if !ok || snaps.fstype != "btrfs" {
		return l, fmt.Errorf(i18n.T("%s is not mounted from its own top-level btrfs subvolume; snapshots are not bootable (ryoku doctor moves it there)"), snapshotsDir)
	}
	l.rootSubvol = strings.Trim(root.root, "/")
	l.snapSubvol = strings.Trim(snaps.root, "/")
	if l.rootSubvol == "" || strings.Contains(l.rootSubvol, "/") || strings.HasPrefix(l.snapSubvol, l.rootSubvol+"/") {
		return l, fmt.Errorf(i18n.T("the snapshots live inside the root subvolume; a restore cannot replace it"))
	}
	uuid, err := blockUUID(boot.source)
	if err != nil {
		return l, err
	}
	l.bootUUID = uuid
	l.bootPrefix = grubBootPrefix(boot)
	l.options, l.rootflags = baseSnapshotOptions(baseCmdline())
	if !strings.Contains(" "+l.options, " root=") {
		return l, fmt.Errorf(i18n.T("no root= in the kernel command line"))
	}
	return l, nil
}

// baseCmdline is the command line Fedora gives its kernels: kernel-install's
// own file when there is one, else the one this boot ran with.
func baseCmdline() string {
	if base := strings.TrimSpace(readText(kernelCmdline)); base != "" {
		return base
	}
	return strings.TrimSpace(readText(procCmdline))
}

// grubBootPrefix is the path GRUB puts before a file under /boot. GRUB reads a
// btrfs from its top level, so a /boot that is a subvolume (Fedora Cloud's
// layout) is found under that subvolume's path.
func grubBootPrefix(boot mountEntry) string {
	if boot.fstype != "btrfs" {
		return ""
	}
	return strings.TrimRight(boot.root, "/")
}

func blockUUID(dev string) (string, error) {
	out, err := sys.RunOut("blkid", "-s", "UUID", "-o", "value", dev)
	if uuid := strings.TrimSpace(out); err == nil && uuid != "" {
		return uuid, nil
	}
	return "", fmt.Errorf(i18n.T("no filesystem UUID for /boot (%s)"), dev)
}

type mountEntry struct {
	root, fstype, source string
}

// parseMountInfo maps each mount point to its btrfs subvolume path (the
// mountinfo root field), filesystem type and source device.
func parseMountInfo(text string) map[string]mountEntry {
	out := map[string]mountEntry{}
	for _, line := range strings.Split(text, "\n") {
		pre, post, ok := strings.Cut(line, " - ")
		if !ok {
			continue
		}
		f, g := strings.Fields(pre), strings.Fields(post)
		if len(f) < 5 || len(g) < 2 {
			continue
		}
		out[f[4]] = mountEntry{root: f[3], fstype: g[0], source: g[1]}
	}
	return out
}

// baseSnapshotOptions splits a kernel command line into the options every
// entry repeats and the rootflags besides subvol=, dropping what each entry
// sets itself: the image, ro/rw, the subvolume, and earlier Ryoku or unit
// overrides.
func baseSnapshotOptions(cmdline string) (opts string, rootflags []string) {
	var keep []string
	for _, tok := range strings.Fields(cmdline) {
		switch {
		case tok == "ro", tok == "rw",
			strings.HasPrefix(tok, "BOOT_IMAGE="),
			strings.HasPrefix(tok, "systemd.unit="),
			strings.HasPrefix(tok, "rd.ryoku."):
		case strings.HasPrefix(tok, "rootflags="):
			for _, o := range strings.Split(strings.TrimPrefix(tok, "rootflags="), ",") {
				if o != "" && !strings.HasPrefix(o, "subvol=") && !strings.HasPrefix(o, "subvolid=") {
					rootflags = append(rootflags, o)
				}
			}
		default:
			keep = append(keep, tok)
		}
	}
	return strings.Join(keep, " "), rootflags
}

// entryOptions is the full cmdline of one entry: the shared options, the root
// mounted read-only from subvol, then the Ryoku argument.
func (l menuLayout) entryOptions(subvol, arg string) string {
	flags := strings.Join(append([]string{"subvol=" + subvol}, l.rootflags...), ",")
	return strings.TrimSpace(l.options + " ro rootflags=" + flags + " " + arg)
}

// readBootSnapshots lists the snapshots newest first, each with the newest
// kernel version its root carries.
func readBootSnapshots(dir string) []bootSnapshot {
	entries, _ := os.ReadDir(dir)
	var out []bootSnapshot
	for _, e := range entries {
		if _, err := strconv.Atoi(e.Name()); err != nil || e.Name() == "0" {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(dir, e.Name(), "info.xml"))
		if err != nil {
			continue
		}
		var s bootSnapshot
		if xml.Unmarshal(raw, &s) != nil || s.Num != e.Name() {
			continue
		}
		s.kver = newestKernel(filepath.Join(dir, e.Name(), "snapshot", "usr/lib/modules"))
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool {
		a, _ := strconv.Atoi(out[i].Num)
		b, _ := strconv.Atoi(out[j].Num)
		return a > b
	})
	return out
}

// newestKernel is the highest kernel version under a modules directory that
// has its vmlinuz, the one that root boots by default.
func newestKernel(dir string) string {
	entries, _ := os.ReadDir(dir)
	best := ""
	for _, e := range entries {
		if !sys.Exists(filepath.Join(dir, e.Name(), "vmlinuz")) {
			continue
		}
		if best == "" || compareVersions(e.Name(), best) > 0 {
			best = e.Name()
		}
	}
	return best
}

// compareVersions orders kernel versions the way rpm does for the cases
// Fedora produces: runs of digits compare as numbers, anything else as text.
func compareVersions(a, b string) int {
	split := func(s string) []string {
		var parts []string
		for len(s) > 0 {
			i := 0
			digit := unicode.IsDigit(rune(s[0]))
			for i < len(s) && unicode.IsDigit(rune(s[i])) == digit {
				i++
			}
			parts = append(parts, s[:i])
			s = s[i:]
		}
		return parts
	}
	pa, pb := split(a), split(b)
	for i := 0; i < len(pa) && i < len(pb); i++ {
		x, errx := strconv.Atoi(pa[i])
		y, erry := strconv.Atoi(pb[i])
		switch {
		case errx == nil && erry == nil && x != y:
			if x < y {
				return -1
			}
			return 1
		case (errx != nil || erry != nil) && pa[i] != pb[i]:
			return strings.Compare(pa[i], pb[i])
		}
	}
	return len(pa) - len(pb)
}

// ensureSnapshotKernel keeps a bootable copy of kver on /boot. The initramfs
// is built from the running system, so it needs kver's modules installed; a
// copy made while they were is kept after the kernel is removed. It is
// rebuilt when what dracut builds it from changed (inputs, a
// dracutFingerprint) and the kernel is still around; a copy that fails to
// rebuild stays as it was, since it still boots.
func ensureSnapshotKernel(kver string, inputs func() string) error {
	dir := filepath.Join(snapshotKernelDir(), kver)
	stamp := filepath.Join(dir, "dracut-inputs")
	src := filepath.Join(modulesDir, kver, "vmlinuz")
	have := sys.Exists(filepath.Join(dir, "vmlinuz")) && sys.Exists(filepath.Join(dir, "initramfs.img"))
	installed := sys.Exists(src)
	if have && (!installed || strings.TrimSpace(readText(stamp)) == inputs()) {
		return nil
	}
	if !installed {
		return fmt.Errorf(i18n.T("kernel %s is no longer installed and has no copy on /boot"), kver)
	}
	if err := buildSnapshotKernel(kver, src, dir); err != nil {
		if have {
			fmt.Printf(i18n.T("boot menu: kept the copy of kernel %s as it was, rebuilding it failed: %v\n"), kver, err)
			return nil
		}
		return err
	}
	_ = os.WriteFile(stamp, []byte(inputs()+"\n"), 0o644)
	return nil
}

// buildSnapshotKernel writes kver's vmlinuz and a fresh initramfs into dir
// beside whatever copy is there, and swaps them in only once both are built.
func buildSnapshotKernel(kver, src, dir string) error {
	vmlinuz, initrd := filepath.Join(dir, "vmlinuz"), filepath.Join(dir, "initramfs.img")
	if free, ok := sys.FreeBytes(bootDir); ok {
		need := fileSize(src) + fileSize(filepath.Join(bootDir, "initramfs-"+kver+".img")) + bootHeadroom
		if free < uint64(need) {
			return fmt.Errorf(i18n.T("/boot has %d MiB free, too little for a copy of kernel %s"), free>>20, kver)
		}
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	defer os.Remove(vmlinuz + ".new")
	defer os.Remove(initrd + ".new")
	if err := sys.CopyFile(src, vmlinuz+".new"); err != nil {
		return err
	}
	build := exec.Command("dracut", "--quiet", "--force", "--add", snapshotDracutMod, "--kver", kver, initrd+".new")
	build.Stderr = os.Stderr
	if err := build.Run(); err != nil {
		return fmt.Errorf(i18n.T("building the initramfs for %s: %w"), kver, err)
	}
	if err := os.Rename(vmlinuz+".new", vmlinuz); err != nil {
		return err
	}
	return os.Rename(initrd+".new", initrd)
}

// dracutFingerprint hashes the contents of every file under paths. Contents,
// not mtimes: rpm installs a file with the time it was built, which can be
// older than a copy built before the update.
func dracutFingerprint(paths []string) string {
	h := sha256.New()
	for _, root := range paths {
		_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			if b, err := os.ReadFile(path); err == nil {
				fmt.Fprintf(h, "%s %d\n", path, len(b))
				h.Write(b)
			}
			return nil
		})
	}
	return hex.EncodeToString(h.Sum(nil))
}

func modTime(path string) time.Time {
	if fi, err := os.Stat(path); err == nil {
		return fi.ModTime()
	}
	return time.Time{}
}

func fileSize(path string) int64 {
	if fi, err := os.Stat(path); err == nil {
		return fi.Size()
	}
	return 0
}

// snapshotsListed reports whether the last sync put any snapshot in the menu:
// a kernel copy exists exactly while a listed snapshot boots it, and unlike
// the menu file under /boot/grub2 it is readable without root.
func snapshotsListed() bool {
	entries, _ := os.ReadDir(snapshotKernelDir())
	for _, e := range entries {
		if sys.Exists(filepath.Join(snapshotKernelDir(), e.Name(), "initramfs.img")) {
			return true
		}
	}
	return false
}

// pruneSnapshotKernels drops the copies no listed snapshot boots.
func pruneSnapshotKernels(used map[string]bool) {
	entries, _ := os.ReadDir(snapshotKernelDir())
	for _, e := range entries {
		if !used[e.Name()] {
			_ = os.RemoveAll(filepath.Join(snapshotKernelDir(), e.Name()))
		}
	}
}

// snapshotEntryID is the GRUB id of a snapshot's look entry; grub2-reboot
// takes it as "<menu>><entry>".
func snapshotEntryID(num string) string {
	return snapshotMenuID + ">" + "ryoku-snapshot-" + num
}

// renderSnapshotMenu is the whole ryoku-snapshots.cfg.
func renderSnapshotMenu(snaps []bootSnapshot, l menuLayout) string {
	var b strings.Builder
	b.WriteString("# Written by `ryoku boot-menu sync` after every snapshot; edits are lost.\n")
	if len(snaps) == 0 {
		return b.String()
	}
	fmt.Fprintf(&b, "submenu 'Ryoku snapshots' --id %s {\n", snapshotMenuID)
	for _, s := range snaps {
		snap := l.snapSubvol + "/" + s.Num + "/snapshot"
		fmt.Fprintf(&b, "  menuentry '%s' --id ryoku-snapshot-%s {\n", grubQuote(snapshotLabel(s)), s.Num)
		writeKernelLines(&b, "    ", l, s.kver, l.entryOptions(snap, "rd.ryoku.preview="+snap))
		b.WriteString("  }\n")
	}
	b.WriteString("}\n")
	return b.String()
}

// writeKernelLines are the lines an entry boots a kernel copy with.
func writeKernelLines(b *strings.Builder, indent string, l menuLayout, kver, options string) {
	fmt.Fprintf(b, "%ssearch --no-floppy --fs-uuid --set=root %s\n", indent, l.bootUUID)
	fmt.Fprintf(b, "%slinux %s/ryoku/snapshots/%s/vmlinuz %s\n", indent, l.bootPrefix, kver, options)
	fmt.Fprintf(b, "%sinitrd %s/ryoku/snapshots/%s/initramfs.img\n", indent, l.bootPrefix, kver)
}

// snapshotLabel: "Snapshot 42, 2026-09-20 10:11 UTC, before ryoku update".
func snapshotLabel(s bootSnapshot) string {
	label := "Snapshot " + s.Num + ", " + shortSnapDate(s.Date) + " UTC"
	// snapper's type reads as a word only for a pair: a pre snapshot is the
	// state before the change it describes, a post one after it.
	when := map[string]string{"pre": "before", "post": "after"}[s.Kind]
	if d := strings.TrimSpace(when + " " + s.Description); d != "" {
		label += ", " + d
	}
	return label
}

// grubQuote makes text safe inside GRUB single quotes, which cannot hold a
// quote at all; control characters go too.
func grubQuote(s string) string {
	return strings.Map(func(r rune) rune {
		if r == '\'' || unicode.IsControl(r) {
			return -1
		}
		return r
	}, s)
}

func readText(path string) string {
	b, _ := os.ReadFile(path)
	return string(b)
}
