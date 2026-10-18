package updater

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// A restore runs from a look boot, the way limine-snapper-restore does on
// Arch: the user boots the snapshot from the menu, sees that it is the one, and
// runs `sudo ryoku boot-menu restore`. The current root subvolume is kept as
// <root>.broken-<time>, a writable snapshot of the booted one takes its name,
// and the next boot (only that one) starts the restored root with the kernel
// copy the look boot runs. /boot is not part of a snapshot, so that first boot
// runs `ryoku boot-menu restored` (ryoku-snapshot-restored.service), which
// brings Fedora's boot entries in line with the kernels the restored root has.
const (
	restoredEntryID = "ryoku-restored"
	// where the look boot's initramfs hook mounts the snapshot it shows.
	previewLower = "/run/ryoku/preview/lower"
	// a set-aside root is deleted this long after a restore; the newest one
	// is always kept.
	brokenRootKeep = 14 * 24 * time.Hour
)

// restoredFlag lives inside the root subvolume, so only the restored root
// sees it; the restore writes it there before that root ever boots. /etc, not
// /var: Fedora Cloud mounts /var from its own subvolume, which would hide it.
const restoredFlag = "/etc/ryoku/snapshot-restored"

var fstabFile = "/etc/fstab"

func restoreSnapshot() error {
	snap := cmdlineValue(readText(procCmdline), "rd.ryoku.preview")
	if snap == "" {
		return errors.New(i18n.T("this is not a snapshot boot: reboot, open Ryoku snapshots in the boot menu, pick the snapshot, then run this again"))
	}
	if !safeSubvolPath(snap) || !strings.HasSuffix(snap, "/snapshot") {
		return fmt.Errorf(i18n.T("refusing snapshot path %q"), snap)
	}
	mounts := parseMountInfo(readText(mountInfo))
	lower, ok := mounts[previewLower]
	if !ok || lower.fstype != "btrfs" {
		return fmt.Errorf(i18n.T("the snapshot is not mounted at %s; this boot cannot restore it"), previewLower)
	}
	rootSubvol := fstabRootSubvol(readText(fstabFile))
	if rootSubvol == "" || strings.Contains(rootSubvol, "/") || !safeSubvolPath(rootSubvol) {
		return fmt.Errorf(i18n.T("%s names no root subvolume this can replace"), fstabFile)
	}
	out, err := sys.RunOut("uname", "-r")
	kver := strings.TrimSpace(out)
	if err != nil || !sys.Exists(filepath.Join(snapshotKernelDir(), kver, "initramfs.img")) {
		return fmt.Errorf(i18n.T("kernel %s has no copy under %s to boot the restored system with"), kver, snapshotKernelDir())
	}
	boot, ok := mounts[bootDir]
	if !ok {
		return errors.New(i18n.T("/boot is not mounted"))
	}
	uuid, err := blockUUID(boot.source)
	if err != nil {
		return err
	}
	opts, flags := baseSnapshotOptions(readText(procCmdline))
	layout := menuLayout{bootUUID: uuid, bootPrefix: grubBootPrefix(boot), options: opts, rootflags: flags}

	top, unmount, err := sys.MountBtrfsTop(lower.source)
	if err != nil {
		return err
	}
	defer unmount()
	root := filepath.Join(top, rootSubvol)
	if !isDir(filepath.Join(top, snap)) || !isDir(root) {
		return fmt.Errorf(i18n.T("%s or %s is missing from the btrfs top level; nothing was changed"), snap, rootSubvol)
	}
	broken := rootSubvol + ".broken-" + time.Now().UTC().Format("20060102-150405")
	if err := os.Rename(root, filepath.Join(top, broken)); err != nil {
		return fmt.Errorf(i18n.T("setting the current root aside: %w; nothing was changed"), err)
	}
	if err := sys.Run("btrfs", "subvolume", "snapshot", filepath.Join(top, snap), root); err != nil {
		_ = os.Rename(filepath.Join(top, broken), root)
		return fmt.Errorf(i18n.T("snapshotting %s failed, the current root is back: %w"), snap, err)
	}
	// From here a failure puts the replaced root back: a restored root without
	// its flag and its one-time entry would boot Fedora's newest kernel, which
	// it may have no modules for, and nothing would mend its boot entries.
	undo := func(cause error) error {
		err := sys.Run("btrfs", "subvolume", "delete", root)
		if err == nil {
			err = os.Rename(filepath.Join(top, broken), root)
		}
		if err != nil {
			return fmt.Errorf(i18n.T("%w; putting the replaced root back failed as well (%v): it is %s at the btrfs top level"), cause, err, broken)
		}
		return fmt.Errorf(i18n.T("%w; the current root is back"), cause)
	}
	if err := sys.WriteFileAtomic(filepath.Join(root, restoredFlag), snap+" "+broken+"\n", 0o644); err != nil {
		return undo(err)
	}
	menu := readText(snapshotMenuCfg())
	if err := sys.WriteFileAtomic(snapshotMenuCfg(), menu+renderRestoredEntry(layout, rootSubvol, kver), 0o644); err != nil {
		return undo(err)
	}
	if err := sys.Run("grub2-reboot", restoredEntryID); err != nil {
		err = undo(fmt.Errorf(i18n.T("pointing the next boot at the restored root: %w"), err))
		if werr := sys.WriteFileAtomic(snapshotMenuCfg(), menu, 0o644); werr != nil {
			return fmt.Errorf(i18n.T("%w; the boot menu still lists \"Ryoku: restored system\" (%v), which now boots the current root until the next snapshot removes it"), err, werr)
		}
		return err
	}
	fmt.Printf(i18n.T("Restored %s. The system it replaced is kept as %s for two weeks.\n"), snap, broken)
	fmt.Println(i18n.T("Reboot now to start the restored system."))
	return nil
}

// renderRestoredEntry boots the restored root once, with the kernel copy the
// look boot ran: the root's own kernels get their boot entries only once it
// runs. `ryoku boot-menu sync` drops it again.
func renderRestoredEntry(l menuLayout, rootSubvol, kver string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "menuentry 'Ryoku: restored system' --id %s {\n", restoredEntryID)
	writeKernelLines(&b, "  ", l, kver, l.entryOptions(rootSubvol, ""))
	b.WriteString("}\n")
	return b.String()
}

// snapshotRestored runs on the first boot of a restored root. Fedora's BLS
// entries for kernels the restored root has no modules for are removed, the
// restored root's kernels get entries (kernel-install also builds their
// initramfs), and the kernel running now, the one the snapshot booted with,
// becomes the default.
func snapshotRestored() error {
	what := strings.Fields(readText(restoredFlag))
	if len(what) < 2 {
		return nil
	}
	fmt.Printf(i18n.T("boot menu: this root was restored from %s; the one it replaced is %s\n"), what[0], what[1])
	listed := blsKernels(blsDir)
	for kver := range listed {
		if !sys.Exists(filepath.Join(modulesDir, kver)) {
			_ = sys.Run("kernel-install", "remove", kver)
		}
	}
	modules, _ := os.ReadDir(modulesDir)
	for _, m := range modules {
		kver := m.Name()
		img := filepath.Join(modulesDir, kver, "vmlinuz")
		if _, ok := listed[kver]; sys.Exists(img) && !ok {
			_ = sys.Run("kernel-install", "add", kver, img)
		}
	}
	if out, err := sys.RunOut("uname", "-r"); err == nil {
		if id, ok := blsKernels(blsDir)[strings.TrimSpace(out)]; ok {
			_ = sys.Run("grub2-set-default", id)
		}
	}
	_ = os.Remove(restoredFlag)
	_ = writeNotice(bootNotice{Action: "snapshot-restored", Snapshot: what[0],
		Detail: fmt.Sprintf(i18n.T("the system was restored from %s. The root it replaced is kept as %s for two weeks."), what[0], what[1]),
		At:     now()})
	return syncSnapshotMenu()
}

// blsKernels maps each kernel version with a plain Fedora BLS entry to that
// entry's id: no rescue image, and no debug or other variant twins. The
// version comes from the entry itself: the token naming the files is the
// machine id the kernel was installed under, which a cloud image's first boot
// changes, so entries from before it carry another one.
func blsKernels(dir string) map[string]string {
	out := map[string]string{}
	matches, _ := filepath.Glob(filepath.Join(dir, "*.conf"))
	sort.Strings(matches)
	for _, m := range matches {
		id := strings.TrimSuffix(filepath.Base(m), ".conf")
		if strings.Contains(id, "~") || strings.Contains(id, "-0-rescue-") {
			continue
		}
		for _, line := range strings.Split(readText(m), "\n") {
			if f := strings.Fields(line); len(f) == 2 && f[0] == "version" {
				if _, seen := out[f[1]]; !seen {
					out[f[1]] = id
				}
				break
			}
		}
	}
	return out
}

// pruneBrokenRoots deletes the roots earlier restores set aside once they are
// older than brokenRootKeep. It runs on every sync, so it reads the subvolume
// list first and mounts the btrfs top level only when one is due.
func pruneBrokenRoots(rootSubvol string) {
	out, err := sys.RunOut("btrfs", "subvolume", "list", "/")
	if err != nil {
		return
	}
	due := expiredBrokenRoots(out, rootSubvol, time.Now())
	if len(due) == 0 {
		return
	}
	root, ok := parseMountInfo(readText(mountInfo))["/"]
	if !ok {
		return
	}
	top, unmount, err := sys.MountBtrfsTop(root.source)
	if err != nil {
		return
	}
	defer unmount()
	for _, name := range due {
		// -R: systemd creates var/lib/portables as a subvolume inside the root
		if err := sys.Run("btrfs", "subvolume", "delete", "-R", filepath.Join(top, name)); err == nil {
			fmt.Printf(i18n.T("boot menu: deleted %s, set aside by a restore\n"), name)
		}
	}
}

// expiredBrokenRoots picks from `btrfs subvolume list` output the set-aside
// roots older than brokenRootKeep, never the newest one.
func expiredBrokenRoots(list, rootSubvol string, now time.Time) []string {
	prefix := rootSubvol + ".broken-"
	var names []string
	for _, line := range strings.Split(list, "\n") {
		_, path, ok := strings.Cut(line, " path ")
		path = strings.TrimPrefix(strings.TrimSpace(path), "<FS_TREE>/")
		if ok && strings.HasPrefix(path, prefix) && !strings.Contains(path, "/") {
			names = append(names, path)
		}
	}
	sort.Strings(names)
	var due []string
	for i, name := range names {
		at, err := time.Parse("20060102-150405", strings.TrimPrefix(name, prefix))
		if i < len(names)-1 && err == nil && now.Sub(at) >= brokenRootKeep {
			due = append(due, name)
		}
	}
	return due
}

// cmdlineValue is the value of key=... on a kernel command line, or "".
func cmdlineValue(cmdline, key string) string {
	for _, tok := range strings.Fields(cmdline) {
		if v, ok := strings.CutPrefix(tok, key+"="); ok {
			return v
		}
	}
	return ""
}

// fstabRootSubvol is the subvolume the fstab entry for / mounts.
func fstabRootSubvol(fstab string) string {
	_, subvol := sys.FstabBtrfsRoot(fstab)
	return subvol
}

// safeSubvolPath accepts a relative btrfs path of plain name characters, the
// shape snapper and Fedora's installer give subvolumes.
func safeSubvolPath(p string) bool {
	if p == "" || strings.HasPrefix(p, "/") || strings.Contains(p, "..") {
		return false
	}
	for _, r := range p {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("._/-", r)) {
			return false
		}
	}
	return true
}

func isDir(path string) bool {
	fi, err := os.Stat(path)
	return err == nil && fi.IsDir()
}
