package sys

import (
	"fmt"
	"os"
	"strings"

	i18n "ryoku-i18n"
)

// FstabBtrfsRoot is the fields of fstab's first active btrfs entry for / that
// names its subvolume with subvol=, and that subvolume; nil when there is
// none. Any other entry for /, a stale one above the real root, is passed by.
func FstabBtrfsRoot(fstab string) ([]string, string) {
	for _, line := range strings.Split(fstab, "\n") {
		f := strings.Fields(line)
		if len(f) < 4 || strings.HasPrefix(f[0], "#") || f[1] != "/" || f[2] != "btrfs" {
			continue
		}
		for _, o := range strings.Split(f[3], ",") {
			if v, ok := strings.CutPrefix(o, "subvol="); ok {
				return f, strings.Trim(v, "/")
			}
		}
	}
	return nil, ""
}

// MountBtrfsTop mounts the top level of the btrfs on dev, where the
// subvolumes of a flat layout sit side by side, and returns the mountpoint and
// the unmount. Each call gets its own directory under /run/ryoku, so one
// caller's unmount never pulls the tree out from under another. A root caller
// runs the commands itself, anyone else through sudo.
func MountBtrfsTop(dev string) (string, func(), error) {
	run, runOut := Run, RunOut
	if os.Geteuid() != 0 {
		run = func(name string, args ...string) error { return Sudo(append([]string{name}, args...)...) }
		runOut = func(name string, args ...string) (string, error) {
			return RunOut("sudo", append([]string{name}, args...)...)
		}
	}
	if err := run("mkdir", "-p", "/run/ryoku"); err != nil {
		return "", nil, err
	}
	out, err := runOut("mktemp", "-d", "-p", "/run/ryoku", "btrfs-top.XXXXXX")
	dir := strings.TrimSpace(out)
	if err != nil || dir == "" {
		return "", nil, fmt.Errorf(i18n.T("making a mountpoint for the btrfs top level: %v"), err)
	}
	if err := run("mount", "-t", "btrfs", "-o", "subvolid=5", dev, dir); err != nil {
		_ = run("rmdir", dir)
		return "", nil, fmt.Errorf(i18n.T("mounting the btrfs top level: %w"), err)
	}
	return dir, func() {
		if run("umount", dir) == nil {
			_ = run("rmdir", dir)
		}
	}, nil
}
