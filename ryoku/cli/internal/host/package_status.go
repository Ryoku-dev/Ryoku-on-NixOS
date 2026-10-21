package host

import (
	"fmt"
	"strings"
)

// packageStatus prints one `name<TAB>state<TAB>source<TAB>reason` line per
// requested catalogue name, in request order: state is installed, available
// or unavailable; source says where an available package comes from (repo or
// aur); reason explains an unavailable one. It answers a whole bundle in one
// call, with one installed-set query and batched availability, because the
// Store asks for it on every catalogue load.
func (a *App) packageStatus(manager PackageManager, names []string) int {
	var rows []packageState
	var ok bool
	switch manager {
	case Pacman:
		rows, ok = a.pacmanStatus(names)
	case DNF:
		rows, ok = a.dnfStatus(names)
	default:
		rows, ok = a.xbpsStatus(names)
	}
	if !ok {
		return ExitFailure
	}
	for _, row := range rows {
		fmt.Fprintf(a.cfg.Stdout, "%s\t%s\t%s\t%s\n", row.name, row.state, row.source, row.reason)
	}
	return ExitOK
}

type packageState struct {
	name, state, source, reason string
}

func installedState(name string) packageState {
	return packageState{name: name, state: "installed", source: "repo"}
}

func availableState(name, source string) packageState {
	return packageState{name: name, state: "available", source: source}
}

func unavailableState(name, reason string) packageState {
	return packageState{name: name, state: "unavailable", reason: reason}
}

// dashReason is the table's note for a row the edition does not package.
func dashReason(mapping packageMapping, fallback string) string {
	if mapping.Note != "" {
		return mapping.Note
	}
	return fallback
}

func lineSet(output string) map[string]bool {
	set := map[string]bool{}
	for _, line := range nonemptyLines(output) {
		set[line] = true
	}
	return set
}

func allIn(names []string, set map[string]bool) bool {
	for _, name := range names {
		if !set[name] {
			return false
		}
	}
	return len(names) > 0
}

// Pacman names need no translation. Anything outside the sync databases comes
// from the AUR, which every pacman host can build from.
func (a *App) pacmanStatus(names []string) ([]packageState, bool) {
	local := a.query("pacman", "-Qq")
	if local.Code != 0 {
		return nil, false
	}
	sync := a.query("pacman", a.pacmanTransactionArgs("-Slq")...)
	if sync.Code != 0 {
		return nil, false
	}
	installed, official := lineSet(local.Output), lineSet(sync.Output)
	rows := make([]packageState, 0, len(names))
	for _, name := range names {
		switch {
		case installed[name]:
			rows = append(rows, installedState(name))
		case official[name]:
			rows = append(rows, availableState(name, "repo"))
		default:
			rows = append(rows, availableState(name, "aur"))
		}
	}
	return rows, true
}

func (a *App) xbpsStatus(names []string) ([]packageState, bool) {
	table, err := a.xbpsTable()
	if err != nil {
		a.failf("%v", err)
		return nil, false
	}
	list := a.query("xbps-query", "-l")
	if list.Code != 0 {
		return nil, false
	}
	installed := map[string]bool{}
	for _, line := range nonemptyLines(list.Output) {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		if match := xbpsPackagePattern.FindStringSubmatch(fields[1]); len(match) == 3 {
			installed[match[1]] = true
		}
	}
	remoteSeen := map[string]bool{}
	remote := func(name string) bool {
		if known, ok := remoteSeen[name]; ok {
			return known
		}
		found := a.probe("xbps-query", "-R", name).Code == 0
		remoteSeen[name] = found
		return found
	}
	isInstalled := func(name string) bool { return installed[name] }
	rows := make([]packageState, 0, len(names))
	for _, name := range names {
		mapping := translatePackage(table, name)
		switch {
		case mapping.Special != "":
			rows = append(rows, unavailableState(name, dashReason(mapping, "Not packaged for Void.")))
		case allIn(mapping.Names, installed):
			rows = append(rows, installedState(name))
		case xbpsRowAvailable(mapping, isInstalled, remote):
			rows = append(rows, availableState(name, "repo"))
		default:
			rows = append(rows, unavailableState(name, "Not in the Void repositories."))
		}
	}
	return rows, true
}

func (a *App) dnfStatus(names []string) ([]packageState, bool) {
	table, err := a.fedoraTable()
	if err != nil {
		a.failf("%v", err)
		return nil, false
	}
	list := a.query("rpm", "-qa", "--qf", "%{NAME}\n")
	if list.Code != 0 {
		return nil, false
	}
	installed := lineSet(list.Output)
	// Names the installed set misses may still be provided by another package
	// (rpm answers provides); the repositories are asked once for all of them.
	var pending []string
	seen := map[string]bool{}
	for _, name := range names {
		mapping := translatePackage(table, name)
		if mapping.Special != "" {
			continue
		}
		for _, native := range mapping.Names {
			if installed[native] || seen[native] {
				continue
			}
			seen[native] = true
			if a.dnfPackageInstalled(native) {
				installed[native] = true
				continue
			}
			pending = append(pending, native)
		}
	}
	available := map[string]bool{}
	if len(pending) > 0 {
		command := a.dnfCommand()
		args := []string{"repoquery", "-y", "--qf", dnfNameQueryFormat}
		if command == "dnf5" {
			args = []string{"repoquery", "-y", "--available", "--qf", dnfNameQueryFormat}
		}
		result := a.query(command, append(args, pending...)...)
		if result.Code != 0 {
			return nil, false
		}
		available = lineSet(result.Output)
		for _, native := range pending {
			if !available[native] && a.dnfPackageAvailable(native) {
				available[native] = true
			}
		}
	}
	rows := make([]packageState, 0, len(names))
	for _, name := range names {
		mapping := translatePackage(table, name)
		switch {
		case mapping.Special != "":
			rows = append(rows, unavailableState(name, dashReason(mapping, "Not packaged for Fedora.")))
		case allIn(mapping.Names, installed):
			rows = append(rows, installedState(name))
		case allInEither(mapping.Names, installed, available):
			rows = append(rows, availableState(name, "repo"))
		default:
			rows = append(rows, unavailableState(name, "Not in the Fedora repositories."))
		}
	}
	return rows, true
}

func allInEither(names []string, first, second map[string]bool) bool {
	for _, name := range names {
		if !first[name] && !second[name] {
			return false
		}
	}
	return len(names) > 0
}
