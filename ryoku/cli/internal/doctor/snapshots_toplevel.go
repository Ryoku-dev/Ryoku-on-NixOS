package doctor

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// On Fedora the snapshots live in their own top-level btrfs subvolume, mounted
// at /.snapshots beside the root subvolume rather than nested inside it. A
// whole-system restore swaps the root subvolume out; snapshots nested in it
// would leave with the old root.
const (
	topLevelSnapshotsSubvol = ".snapshots"
	fstabPath               = "/etc/fstab"
)

// snapshotsFstabLine derives the /.snapshots entry from the btrfs root's: the
// same device and options with its own subvolume. It is "" when fstab has no
// btrfs root that names a subvolume, a layout this cannot extend.
func snapshotsFstabLine(fstab string) string {
	f, _ := sys.FstabBtrfsRoot(fstab)
	if f == nil {
		return ""
	}
	var opts []string
	for _, o := range strings.Split(f[3], ",") {
		switch {
		case strings.HasPrefix(o, "subvol="):
			opts = append(opts, "subvol="+topLevelSnapshotsSubvol)
		case strings.HasPrefix(o, "subvolid="):
		default:
			opts = append(opts, o)
		}
	}
	return strings.Join([]string{f[0], "/.snapshots", "btrfs", strings.Join(opts, ","), "0", "0"}, " ")
}

// fstabMounts reports whether fstab has an active entry for target.
func fstabMounts(fstab, target string) bool {
	for _, line := range strings.Split(fstab, "\n") {
		f := strings.Fields(line)
		if len(f) >= 2 && !strings.HasPrefix(f[0], "#") && f[1] == target {
			return true
		}
	}
	return false
}

// createTopLevelSnapshots creates the top-level snapshots subvolume, adds its
// fstab entry, and mounts it at /.snapshots. A subvolume or fstab entry an
// earlier run left behind is adopted, not recreated.
func createTopLevelSnapshots() error {
	raw, err := os.ReadFile(fstabPath)
	if err != nil {
		return err
	}
	fstab := string(raw)
	line := snapshotsFstabLine(fstab)
	if line == "" {
		return fmt.Errorf(i18n.T("the root entry in %s names no btrfs subvolume"), fstabPath)
	}
	dev, err := sys.RunOut("findmnt", "-nvo", "SOURCE", "/")
	if dev = strings.TrimSpace(dev); err != nil || dev == "" {
		return fmt.Errorf(i18n.T("no device for the root filesystem"))
	}
	top, unmount, err := sys.MountBtrfsTop(dev)
	if err != nil {
		return err
	}
	sub := filepath.Join(top, topLevelSnapshotsSubvol)
	if sys.Run("sudo", "test", "-d", sub) != nil {
		err = sys.Run("sudo", "btrfs", "subvolume", "create", sub)
	}
	unmount()
	if err != nil {
		return fmt.Errorf(i18n.T("creating the %s subvolume: %w"), topLevelSnapshotsSubvol, err)
	}
	if !fstabMounts(fstab, "/.snapshots") {
		if !strings.HasSuffix(fstab, "\n") {
			fstab += "\n"
		}
		if err := writeRootFile(fstabPath, fstab+line+"\n", "0644"); err != nil {
			return fmt.Errorf(i18n.T("adding /.snapshots to %s: %w"), fstabPath, err)
		}
		_ = sys.Run("sudo", "restorecon", fstabPath)
	}
	_ = sys.Run("sudo", "systemctl", "daemon-reload")
	if err := sys.Run("sudo", "mkdir", "-p", "/.snapshots"); err != nil {
		return err
	}
	// systemd mounts it through the unit its fstab generator made, which the
	// snapshot menu's RequiresMountsFor may already have started; a plain
	// mount on top of that would stack a second one.
	unit, err := sys.RunOut("systemd-escape", "-p", "--suffix=mount", "/.snapshots")
	if err != nil {
		return fmt.Errorf(i18n.T("naming the /.snapshots mount unit: %w"), err)
	}
	if err := sys.Run("sudo", "systemctl", "start", strings.TrimSpace(unit)); err != nil {
		return fmt.Errorf(i18n.T("mounting /.snapshots: %w"), err)
	}
	_ = sys.Run("sudo", "restorecon", "-R", "/.snapshots")
	return nil
}

// errSnapshotsInUse: a nested /.snapshots that already holds snapshots is not
// moved. They are read-only subvolumes of the old layout, and only the user
// decides whether they go.
var errSnapshotsInUse = errors.New("/.snapshots holds snapshots")

// moveNestedSnapshots replaces an empty /.snapshots subvolume nested in the
// root with the top-level one. The fstab entry it needs is worked out first,
// and a nested one is made again if the move fails halfway, so snapper is
// never left without /.snapshots.
func moveNestedSnapshots() error {
	raw, err := os.ReadFile(fstabPath)
	if err != nil {
		return err
	}
	if snapshotsFstabLine(string(raw)) == "" {
		return fmt.Errorf(i18n.T("the root entry in %s names no btrfs subvolume"), fstabPath)
	}
	out, err := sys.RunOut("sudo", "find", "/.snapshots", "-mindepth", "1", "-maxdepth", "1", "-print", "-quit")
	if err != nil {
		return fmt.Errorf(i18n.T("reading /.snapshots: %w"), err)
	}
	if strings.TrimSpace(out) != "" {
		return errSnapshotsInUse
	}
	if err := sys.Run("sudo", "btrfs", "subvolume", "delete", "/.snapshots"); err != nil {
		return fmt.Errorf(i18n.T("removing the nested /.snapshots subvolume: %w"), err)
	}
	if err := createTopLevelSnapshots(); err != nil {
		if !isMountPoint("/.snapshots") {
			_ = sys.Run("sudo", "rmdir", "/.snapshots")
			_ = sys.Run("sudo", "btrfs", "subvolume", "create", "/.snapshots")
		}
		return err
	}
	return nil
}

func snapshotsMoveFailed(err error) recResult {
	if errors.Is(err, errSnapshotsInUse) {
		return warnRes(i18n.T("/.snapshots sits inside the root subvolume and already holds snapshots, so they cannot be booted or restored")).
			withFix(i18n.T("delete them (sudo snapper -c root list, then sudo snapper -c root delete <first>-<last>), then run ryoku doctor to move /.snapshots"))
	}
	return failRes(i18n.T("moving /.snapshots to its own subvolume: %v"), err).
		withFix(i18n.T("give /.snapshots its own top-level btrfs subvolume in /etc/fstab, then re-run ryoku doctor"))
}

// isMountPoint reports whether something is mounted exactly at path.
func isMountPoint(path string) bool {
	return mountFSRoot(path) != ""
}

// mountFSRoot is the subvolume path of what is mounted exactly at path, or ""
// when nothing is.
func mountFSRoot(path string) string {
	out, err := sys.RunOut("findmnt", "-n", "-o", "FSROOT", "--mountpoint", path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

// insideSubvol reports whether subvolume path sub lies inside parent.
func insideSubvol(sub, parent string) bool {
	parent = strings.TrimSuffix(parent, "/")
	return parent != "" && strings.HasPrefix(sub, parent+"/")
}
