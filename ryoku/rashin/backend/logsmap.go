package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	wm "ryoku-wm"
)

// logsmap.go generates logs.md: where the logs live on this machine, discovered
// at index time, and the one command that gathers them. It never reads logs,
// only records the commands and paths an agent (or a person) runs to dig in.

const logsMapHeader = "# Logs\n" +
	"\n" +
	"Where the logs live on this machine and the one command that gathers them.\n" +
	"When something breaks, run `ryoku-rashin logs <app>` first, then dig with the\n" +
	"commands below. Generated: the content between the markers is overwritten on\n" +
	"every reindex."

// writeLogsMapVaultDoc writes logs.md.
func writeLogsMapVaultDoc() error {
	return writeVaultDoc("logs.md", logsMapHeader, logsMapBody())
}

func logsMapBody() string {
	var b strings.Builder

	b.WriteString("## Start here\n\n")
	b.WriteString("`ryoku-rashin logs <target>` gathers the units, the journal, coredumps, the app's own log files, and its package history for any app or Ryoku component, in one bounded bundle headed by the exact command behind each section.\n\n")
	b.WriteString("Component aliases: `shell`, `wallpaper`, `hub`, `idle`, `audio`, `portals`, `updates`, `compositor`, `rashin`. Anything else is treated as a program name.\n\n")
	fmt.Fprintf(&b, "Default window is the last %s, %d lines per source; widen with `--since 1d` or `--lines 200`.\n\n", logsDefaultSince, logsDefaultLines)

	b.WriteString("## Ryoku systemd user units\n\n")
	if units := presentRyokuUnits(); len(units) > 0 {
		for _, u := range units {
			fmt.Fprintf(&b, "- `%s`: `journalctl --user -u %s -e`\n", u, u)
		}
		b.WriteString("\n")
	} else {
		b.WriteString("None detected right now.\n\n")
	}

	b.WriteString("## Quickshell instances\n\n")
	if list, ok := probe(logsProbeTimeout, "qs", "list", "--all"); ok {
		rows := quickshellInstances(list)
		if len(rows) > 0 {
			// By config dir, not instance id: an id changes every restart and this
			// doc outlives it.
			for _, r := range rows {
				dir := tildeAbbrev(filepath.Dir(r.config))
				fmt.Fprintf(&b, "- %s: `qs log -p %s -t 200`\n", dir, dir)
			}
			b.WriteString("\n")
		} else {
			b.WriteString("None running right now.\n\n")
		}
	} else {
		b.WriteString("`qs` is not available.\n\n")
	}

	b.WriteString("## Compositor\n\n")
	if det := wm.Detect(); det.Name != "" {
		fmt.Fprintf(&b, "Detected `%s` (via %s). Journal: `journalctl --user _COMM=%s -e`.\n", det.Name, det.Source, det.Name)
		if p := compositorRuntimeLog(det.Name); p != "" {
			fmt.Fprintf(&b, "Runtime log: `%s`.\n", p)
		}
		b.WriteString("Or run `ryoku-rashin logs compositor`.\n\n")
	} else {
		b.WriteString("No window-manager provider detected.\n\n")
	}

	b.WriteString("## Wallpaper (ryogami)\n\n")
	if files := discoverLogFiles([]string{filepath.Join(home(), ".cache", "ryogami")}, logsFileDepth, 6); len(files) > 0 {
		for _, f := range files {
			fmt.Fprintf(&b, "- `%s`\n", f)
		}
		b.WriteString("\n")
	} else {
		b.WriteString("No `*.log` under `~/.cache/ryogami` right now; the service journal is `journalctl --user -u ryogami.service -e`.\n\n")
	}

	b.WriteString("## Updates and doctor\n\n")
	state := filepath.Join(home(), ".local", "state", "ryoku")
	for _, f := range []struct{ path, what string }{
		{filepath.Join(state, "doctor-report.txt"), "the last doctor run"},
		{filepath.Join(state, "update-log.txt"), "the last update run"},
	} {
		mark := ""
		if !fileExists(f.path) {
			mark = " (not present yet)"
		}
		fmt.Fprintf(&b, "- `%s`: %s%s\n", f.path, f.what, mark)
	}
	switch logsPackageManager() {
	case "dnf":
		b.WriteString("- `dnf history list`: package transactions; an upgrade right before a breakage is the classic cause.\n")
	case "xbps":
		b.WriteString("- `/var/log/xbps.log`: package transactions; an upgrade right before a breakage is the classic cause.\n")
	case "pacman":
		b.WriteString("- `/var/log/pacman.log`: package transactions; an upgrade right before a breakage is the classic cause.\n")
	default:
		b.WriteString("- Native package history is unavailable until `ryoku-host pkgmgr` identifies the host.\n")
	}
	b.WriteString("- `ryoku-rashin logs updates` bundles the doctor report, update log, and native package history.\n\n")

	b.WriteString("## Crashes\n\n")
	b.WriteString("`coredumpctl list` lists every dump; `coredumpctl info <binary>` heads the newest. `ryoku-rashin logs <app>` folds in a binary's dumps and any OOM kills naming it.\n")

	return b.String()
}

// qsInstance is one running Quickshell instance's id and config path.
type qsInstance struct {
	id     string
	config string
}

// quickshellInstances parses `qs list --all` into id + config-path pairs.
func quickshellInstances(list string) []qsInstance {
	var out []qsInstance
	var cur string
	for _, l := range strings.Split(list, "\n") {
		t := strings.TrimSpace(l)
		if strings.HasPrefix(t, "Instance ") && strings.HasSuffix(t, ":") {
			cur = strings.TrimSuffix(strings.TrimPrefix(t, "Instance "), ":")
			continue
		}
		if strings.HasPrefix(t, "Config path:") && cur != "" {
			out = append(out, qsInstance{id: cur, config: strings.TrimSpace(strings.TrimPrefix(t, "Config path:"))})
			cur = ""
		}
	}
	return out
}

// presentRyokuUnits lists the loaded Ryoku systemd user units on this box,
// sorted and unique, so logs.md names only what actually exists here.
func presentRyokuUnits() []string {
	out, ok := probe(logsProbeTimeout, "systemctl", "--user", "list-units", "--all", "--no-legend", "--plain")
	if !ok {
		return nil
	}
	seen := map[string]bool{}
	var units []string
	for _, l := range strings.Split(out, "\n") {
		fields := strings.Fields(l)
		if len(fields) == 0 {
			continue
		}
		u := fields[0]
		if !strings.HasSuffix(u, ".service") {
			continue
		}
		low := strings.ToLower(u)
		if !strings.HasPrefix(low, "ryoku") && !strings.HasPrefix(low, "ryogami") {
			continue
		}
		if seen[u] {
			continue
		}
		seen[u] = true
		units = append(units, u)
	}
	sort.Strings(units)
	return units
}

// compositorRuntimeLog returns the compositor's runtime log file when it writes
// one, resolved through the seam's config-dir name under XDG_RUNTIME_DIR rather
// than a hardcoded compositor path.
func compositorRuntimeLog(name string) string {
	sub := wm.ConfigDir(name)
	rt := os.Getenv("XDG_RUNTIME_DIR")
	if sub == "" || rt == "" {
		return ""
	}
	files := discoverLogFiles([]string{filepath.Join(rt, sub)}, logsFileDepth, 1)
	if len(files) == 0 {
		return ""
	}
	return files[0]
}
