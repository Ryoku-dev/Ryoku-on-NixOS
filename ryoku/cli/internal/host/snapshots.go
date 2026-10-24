package host

import (
	"fmt"
	"os"
	"strings"

	i18n "ryoku-i18n"
)

const (
	snapshotsUnavailableReason = "Snapshots are not available on this host, so updates cannot be rolled back."
	snapshotPreviewReason      = "This boot runs %s read-only and keeps its changes in RAM. Run `sudo ryoku boot-menu restore` to make it the system, or reboot to go back."
)

// Snapshots reports whether this host provides Ryoku's snapper-based safety net.
// A snapshot look boot does not: its root is an overlay snapper cannot open, and
// a snapshot taken or a config changed there would be gone at the next boot.
func (a *App) Snapshots() (supported bool, reason string) {
	manager, err := a.PackageManager()
	if err != nil || (manager != Pacman && manager != XBPS && manager != DNF) {
		return false, i18n.T(snapshotsUnavailableReason)
	}
	if snap := a.SnapshotPreview(); snap != "" {
		return false, fmt.Sprintf(i18n.T(snapshotPreviewReason), snapshotLabel(snap))
	}
	return true, ""
}

// SnapshotPreview names the subvolume this boot looks at (rd.ryoku.preview,
// set by the Ryoku snapshots boot menu), or "" for an ordinary boot.
func (a *App) SnapshotPreview() string {
	data, err := os.ReadFile(a.cfg.ProcCmdline)
	if err != nil {
		return ""
	}
	for _, field := range strings.Fields(string(data)) {
		if value, ok := strings.CutPrefix(field, "rd.ryoku.preview="); ok {
			return value
		}
	}
	return ""
}

// snapshotLabel turns snapper's .snapshots/<n>/snapshot into "snapshot <n>".
func snapshotLabel(path string) string {
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) == 3 && parts[0] == ".snapshots" && parts[2] == "snapshot" {
		return fmt.Sprintf(i18n.T("snapshot %s"), parts[1])
	}
	return path
}

func (a *App) Snapshot(args []string) int {
	supported, reason := a.Snapshots()
	if !supported {
		if reason != "" {
			fmt.Fprintln(a.cfg.Stdout, reason)
		}
		return ExitNotProvided
	}
	if len(args) == 0 {
		return ExitOK
	}
	if len(args) != 2 || args[0] != "create" || strings.TrimSpace(args[1]) == "" {
		return ExitUsage
	}
	if !a.cfg.Runner.LookPath("snapper") {
		fmt.Fprintln(a.cfg.Stderr, i18n.T("snapper is not installed"))
		return ExitAbsent
	}
	if info, err := os.Stat(a.cfg.SnapperRootConfig); err != nil || info.IsDir() {
		fmt.Fprintln(a.cfg.Stderr, i18n.T("snapper's root configuration is not available"))
		return ExitAbsent
	}
	result := a.run("snapper", "-c", "root", "create", "-c", "number", "--description", args[1])
	if result.Code != ExitOK {
		return commandExit(result)
	}
	return commandExit(a.run("snapper", "-c", "root", "cleanup", "number"))
}
