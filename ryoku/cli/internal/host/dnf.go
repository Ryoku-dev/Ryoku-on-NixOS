package host

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const (
	fedoraPackageTable = "/usr/share/ryoku/packages/fedora.tsv"
	dnfNameQueryFormat = "%{name}\n"
	dnfRepoQueryFormat = "%{name}\t%{epoch}:%{version}-%{release}\n"
)

// DNFCommand returns the DNF implementation available on this host.
func DNFCommand() string {
	return selectDNFCommand(func(name string) bool {
		_, err := exec.LookPath(name)
		return err == nil
	})
}

func (a *App) dnfCommand() string {
	return selectDNFCommand(a.cfg.Runner.LookPath)
}

func selectDNFCommand(lookPath func(string) bool) string {
	if lookPath("dnf5") {
		return "dnf5"
	}
	return "dnf"
}

// DNF keeps imported repository keys below the cache directory even after
// `dnf clean all`; remove the whole per-URL cache when the base URL changes.
func (a *App) clearDNFRepoCache() error {
	dirs := []string{"/var/cache/libdnf5", "/var/cache/dnf"}
	if override := strings.TrimSpace(a.getenv("RYOKU_DNF_CACHE_DIR")); override != "" {
		dirs = []string{override}
	}
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return err
		}
		for _, entry := range entries {
			if entry.Name() != ryokuRepoName && !strings.HasPrefix(entry.Name(), ryokuRepoName+"-") {
				continue
			}
			if err := os.RemoveAll(filepath.Join(dir, entry.Name())); err != nil {
				return err
			}
		}
	}
	return nil
}

func (a *App) fedoraTablePath() string {
	if path := a.getenv("RYOKU_HOST_PKG_TABLE"); path != "" {
		return path
	}
	if a.cfg.PackageTable != "" && a.cfg.PackageTable != "/usr/share/ryoku/packages/void.tsv" {
		return a.cfg.PackageTable
	}
	return fedoraPackageTable
}

func (a *App) fedoraTable() (packageTable, error) {
	table, err := a.packageTable(a.fedoraTablePath(), "fedora")
	if err != nil {
		return nil, err
	}
	return a.withOverlay(table, "fedora")
}

func (a *App) dnfPackageWhy(name string) int {
	table, err := a.fedoraTable()
	if err != nil {
		return a.failf("%v", err)
	}
	return a.packageWhy(table, name, "Not packaged for Fedora.")
}

func (a *App) dnf(args []string) int {
	if len(args) == 0 {
		return ExitUsage
	}
	verb, rest := args[0], args[1:]
	switch verb {
	case "count":
		if len(rest) > 1 || len(rest) == 1 && rest[0] != "--foreign" {
			return ExitUsage
		}
		return a.dnfCount(len(rest) == 1)
	case "install-file":
		if len(rest) == 0 {
			return ExitUsage
		}
		return commandExit(a.run(a.dnfCommand(), append([]string{"install", "-y"}, rest...)...))
	case "owner":
		if len(rest) != 1 {
			return ExitUsage
		}
		result := a.query("rpm", "-qf", "--qf", "%{NAME}\n", rest[0])
		if result.Code != 0 {
			return ExitFalse
		}
		fmt.Fprintln(a.cfg.Stdout, strings.TrimSpace(result.Output))
		return ExitOK
	case "installed", "available", "remove", "local", "explicit":
		if len(rest) == 0 {
			return ExitUsage
		}
	case "version":
		if len(rest) != 1 {
			return ExitUsage
		}
	case "install":
	default:
		return ExitUsage
	}

	upgrade := false
	if verb == "install" {
		for len(rest) > 0 && strings.HasPrefix(rest[0], "--") {
			switch rest[0] {
			case "--upgrade":
				upgrade = true
				rest = rest[1:]
			case "--aur":
				rest = rest[1:]
			case "--overwrite":
				if len(rest) < 2 {
					return ExitUsage
				}
				rest = rest[2:]
			default:
				return ExitUsage
			}
		}
		if len(rest) == 0 {
			return ExitUsage
		}
	}
	if verb == "available" && rest[0] == "--aur" {
		rest = rest[1:]
		if len(rest) == 0 {
			return ExitUsage
		}
	}

	table, err := a.fedoraTable()
	if err != nil {
		return a.failf("read Fedora package table: %v", err)
	}
	if verb == "local" {
		for _, name := range rest {
			mapping := translatePackage(table, name)
			fmt.Fprintln(a.cfg.Stdout, strings.Join(mapping.Names, " "))
		}
		return ExitOK
	}
	translated, unavailable := translatePackages(table, rest)
	if len(unavailable) > 0 {
		if verb == "installed" || verb == "version" {
			return ExitFalse
		}
		if verb == "available" {
			return ExitNotProvided
		}
		a.reportUnavailablePackages(table, unavailable)
		return ExitNotProvided
	}

	switch verb {
	case "installed":
		for _, name := range translated {
			if !a.dnfPackageInstalled(name) {
				return ExitFalse
			}
		}
		return ExitOK
	case "available":
		for _, name := range translated {
			if !a.dnfPackageAvailable(name) {
				return ExitFalse
			}
		}
		return ExitOK
	case "version":
		args := []string{"-q", "--whatprovides", "--qf", "%{EPOCHNUM}:%{VERSION}-%{RELEASE}\n", translated[0]}
		if rpmArchQualified(translated[0]) {
			args = []string{"-q", "--qf", "%{EPOCHNUM}:%{VERSION}-%{RELEASE}\n", translated[0]}
		}
		result := a.query("rpm", args...)
		if result.Code != 0 {
			return ExitFalse
		}
		fmt.Fprintln(a.cfg.Stdout, strings.TrimSpace(result.Output))
		return ExitOK
	case "install":
		action := "install"
		if upgrade {
			action = "upgrade"
		} else {
			pending := make([]string, 0, len(translated))
			for _, name := range translated {
				if !a.dnfPackageInstalled(name) {
					pending = append(pending, name)
				}
			}
			if len(pending) == 0 {
				return ExitOK
			}
			translated = pending
		}
		command := []string{action, "-y", "--setopt=install_weak_deps=False"}
		return commandExit(a.run(a.dnfCommand(), append(command, translated...)...))
	case "remove":
		installed := make([]string, 0, len(translated))
		for _, name := range translated {
			if a.dnfPackageInstalled(name) {
				installed = append(installed, name)
			}
		}
		if len(installed) == 0 {
			return ExitOK
		}
		return commandExit(a.run(a.dnfCommand(), append([]string{"remove", "-y", "--setopt=clean_requirements_on_remove=False"}, installed...)...))
	case "explicit":
		mark := "user"
		if a.dnfCommand() == "dnf" {
			mark = "install"
		}
		return commandExit(a.run(a.dnfCommand(), append([]string{"mark", mark, "-y"}, translated...)...))
	}
	return ExitUsage
}

// rpmArchQualified reports a name spelled with its architecture, the way Fedora
// names a 32-bit package (mesa-dri-drivers.i686). That is a package spec, not a
// capability: --whatprovides never matches it, so it is queried as a name.
func rpmArchQualified(name string) bool {
	dot := strings.LastIndexByte(name, '.')
	if dot <= 0 {
		return false
	}
	switch name[dot+1:] {
	case "i686", "x86_64", "aarch64", "noarch":
		return true
	}
	return false
}

func (a *App) dnfPackageInstalled(name string) bool {
	if rpmArchQualified(name) {
		return a.probe("rpm", "-q", "--quiet", name).Code == 0
	}
	return a.probe("rpm", "-q", "--whatprovides", "--quiet", name).Code == 0
}

func (a *App) dnfPackageAvailable(name string) bool {
	command := a.dnfCommand()
	spec := "--whatprovides=" + name
	if rpmArchQualified(name) {
		spec = name
	}
	args := []string{"repoquery", "-y", spec, "--qf", dnfNameQueryFormat}
	if command == "dnf5" {
		args = []string{"repoquery", "-y", "--available", spec, "--qf", dnfNameQueryFormat}
	}
	result := a.query(command, args...)
	return result.Code == 0 && strings.TrimSpace(result.Output) != ""
}

func (a *App) dnfCount(foreign bool) int {
	if !foreign {
		result := a.query("rpm", "-qa", "--qf", "%{NAME}\n")
		if result.Code != 0 {
			return ExitFailure
		}
		fmt.Fprintln(a.cfg.Stdout, countLines(result.Output))
		return ExitOK
	}
	command := a.dnfCommand()
	args := []string{"repoquery", "-y", "--extras", "--qf", dnfNameQueryFormat}
	result := a.query(command, args...)
	if result.Code == 0 {
		fmt.Fprintln(a.cfg.Stdout, len(nonemptyLines(result.Output)))
		return ExitOK
	}
	if command != "dnf" {
		return ExitFailure
	}
	result = a.query(command, "list", "-y", "--extras")
	if result.Code != 0 {
		return ExitFailure
	}
	fmt.Fprintln(a.cfg.Stdout, countDNFListRows(result.Output))
	return ExitOK
}

func countDNFListRows(output string) int {
	count := 0
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && strings.Contains(fields[0], ".") && !strings.HasPrefix(line, " ") {
			count++
		}
	}
	return count
}

func (a *App) dnfOrphans() ([]string, error) {
	command := a.dnfCommand()
	args := []string{"repoquery", "-y", "--unneeded", "--qf", dnfNameQueryFormat}
	result := a.query(command, args...)
	if result.Code == 0 {
		return nonemptyLines(result.Output), nil
	}
	if command != "dnf" {
		return nil, commandError(command, args, result)
	}
	fallback := []string{"autoremove", "-y", "--assumeno"}
	result = a.query(command, fallback...)
	if result.Code != 0 && strings.TrimSpace(result.Output) == "" {
		return nil, commandError(command, fallback, result)
	}
	return parseDNFAutoremove(result.Output), nil
}

func nonemptyLines(output string) []string {
	var values []string
	for _, line := range strings.Split(output, "\n") {
		if line = strings.TrimSpace(line); line != "" {
			values = append(values, line)
		}
	}
	return values
}

func parseDNFAutoremove(output string) []string {
	seen := map[string]bool{}
	var packages []string
	inPackages := false
	for _, raw := range strings.Split(output, "\n") {
		line := strings.TrimSpace(raw)
		switch {
		case line == "Removing:" || line == "Removing unused dependencies:":
			inPackages = true
			continue
		case line == "Transaction Summary":
			inPackages = false
		}
		if !inPackages || line == "" || strings.HasPrefix(line, "=") || strings.HasPrefix(line, "Package ") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 4 || seen[fields[0]] {
			continue
		}
		seen[fields[0]] = true
		packages = append(packages, fields[0])
	}
	sort.Strings(packages)
	return packages
}
