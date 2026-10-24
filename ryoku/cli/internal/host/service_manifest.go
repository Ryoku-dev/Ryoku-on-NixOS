package host

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

type serviceManifestEntry struct {
	ID          string
	Scope       string
	Activation  string
	SystemdUnit string
	RunitName   string
	DisableRule string
}

func readServiceManifest(path string) ([]serviceManifestEntry, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var entries []serviceManifestEntry
	seen := make(map[string]bool)
	scanner := bufio.NewScanner(file)
	for line := 1; scanner.Scan(); line++ {
		text := scanner.Text()
		if text == "" || strings.HasPrefix(text, "#") || text == "id\tscope\tactivation\tsystemd_unit\trunit_service\tuser_disable_rule" {
			continue
		}
		fields := strings.Split(text, "\t")
		if len(fields) != 6 {
			return nil, fmt.Errorf(i18n.T("%s:%d: want 6 tab-separated fields"), path, line)
		}
		entry := serviceManifestEntry{
			ID: fields[0], Scope: fields[1], Activation: fields[2],
			SystemdUnit: fields[3], RunitName: fields[4], DisableRule: fields[5],
		}
		if err := validateServiceManifestEntry(entry); err != nil {
			return nil, fmt.Errorf(i18n.T("%s:%d: %w"), path, line, err)
		}
		if seen[entry.ID] {
			return nil, fmt.Errorf(i18n.T("%s:%d: duplicate service id %s"), path, line, entry.ID)
		}
		seen[entry.ID] = true
		entries = append(entries, entry)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return entries, nil
}

func validateServiceManifestEntry(entry serviceManifestEntry) error {
	if entry.ID == "" || strings.ContainsAny(entry.ID, "/\\") {
		return fmt.Errorf(i18n.T("invalid service id %q"), entry.ID)
	}
	if entry.Scope != "system" && entry.Scope != "user" {
		return fmt.Errorf(i18n.T("invalid scope %q for %s"), entry.Scope, entry.ID)
	}
	switch entry.Activation {
	case "boot", "enable-once", "conditional":
		if entry.Scope != "system" {
			return fmt.Errorf(i18n.T("activation %q requires system scope"), entry.Activation)
		}
	case "session", "session-core", "session-global":
		if entry.Scope != "user" {
			return fmt.Errorf(i18n.T("activation %q requires user scope"), entry.Activation)
		}
	case "on-demand":
	default:
		return fmt.Errorf(i18n.T("invalid activation %q for %s"), entry.Activation, entry.ID)
	}
	if entry.SystemdUnit == "" || entry.RunitName == "" {
		return fmt.Errorf(i18n.T("empty implementation for %s; use - when absent"), entry.ID)
	}
	if entry.RunitName != "-" && strings.ContainsAny(entry.RunitName, "/\\") {
		return fmt.Errorf(i18n.T("invalid runit service %q"), entry.RunitName)
	}
	switch {
	case entry.DisableRule == "none", entry.DisableRule == "preserve":
	case strings.HasPrefix(entry.DisableRule, "preserve:/"):
	case strings.HasPrefix(entry.DisableRule, "condition:/"):
	default:
		return fmt.Errorf(i18n.T("invalid user-disable rule %q for %s"), entry.DisableRule, entry.ID)
	}
	if entry.Activation == "conditional" && !strings.HasPrefix(entry.DisableRule, "condition:/") {
		return fmt.Errorf(i18n.T("conditional service %s needs a condition rule"), entry.ID)
	}
	return nil
}

func (a *App) ServiceReconcile(scope string, checkOnly bool) int {
	user := scope == "--user"
	if !user && scope != "--system" {
		return ExitUsage
	}
	if !user && !checkOnly && a.cfg.UID != 0 {
		return a.failf("%s", i18n.T("svc reconcile --system must run as root unless --check is used"))
	}
	entries, err := readServiceManifest(a.cfg.ServiceManifest)
	if err != nil {
		return a.failf(i18n.T("read service manifest: %v"), err)
	}
	init, err := a.Init()
	if err != nil {
		return a.failf("%v", err)
	}
	if init == Systemd {
		return a.reconcileSystemdServices(entries, user, checkOnly)
	}
	if user {
		return a.reconcileRunitUserServices(entries, checkOnly)
	}
	return a.reconcileRunitSystemServices(entries, checkOnly)
}

func (a *App) reconcileSystemdServices(entries []serviceManifestEntry, user, checkOnly bool) int {
	scope := "system"
	if user {
		scope = "user"
	}
	changed := false
	if user {
		adopted, err := a.adoptSystemdUserBaseline(entries, checkOnly)
		if err != nil {
			return a.failf(i18n.T("record existing user service choices: %v"), err)
		}
		changed = adopted
	}
	for _, entry := range entries {
		if !user && entry.Scope == "user" && entry.Activation == "session-global" {
			if entry.SystemdUnit == "-" || !fileExists(filepath.Join(a.cfg.SystemdUserDir, entry.SystemdUnit)) {
				continue
			}
			enabled := a.probe("systemctl", "--global", "is-enabled", "--quiet", entry.SystemdUnit).Code == 0
			if enabled {
				continue
			}
			changed = true
			if !checkOnly && commandExit(a.run("systemctl", "--global", "enable", entry.SystemdUnit)) != ExitOK {
				return ExitFailure
			}
			continue
		}
		if !user && a.isSystemdGlobalUserEntry(entry) {
			marker := a.serviceActivationMarker(entry, false)
			if fileExists(marker) {
				continue
			}
			changed = true
			if checkOnly {
				continue
			}
			if commandExit(a.run("systemctl", "--global", "enable", entry.SystemdUnit)) != ExitOK {
				return ExitFailure
			}
			if err := writeServiceMarker(marker); err != nil {
				return a.failf(i18n.T("record service activation %s: %v"), entry.ID, err)
			}
			continue
		}
		if entry.Scope != scope || entry.SystemdUnit == "-" || !a.systemdManifestUnitExists(user, entry.SystemdUnit) {
			continue
		}
		switch entry.Activation {
		case "boot":
			if a.systemdManifestUnitEnabled(user, entry.SystemdUnit) {
				continue
			}
			changed = true
			if !checkOnly && a.enableSystemdManifestUnit(user, false, entry.SystemdUnit) != ExitOK {
				return ExitFailure
			}
		case "enable-once", "session", "session-global":
			marker := a.serviceActivationMarker(entry, user)
			if entry.Activation == "session-global" && a.systemdManifestUnitEnabled(user, entry.SystemdUnit) {
				continue
			}
			if a.serviceActivationRecorded(entry, user) {
				continue
			}
			changed = true
			if checkOnly {
				continue
			}
			startNow := a.systemdManifestShouldStartNow(user)
			if a.enableSystemdManifestUnit(user, startNow, entry.SystemdUnit) != ExitOK {
				return ExitFailure
			}
			if err := writeServiceMarker(marker); err != nil {
				return a.failf(i18n.T("record service activation %s: %v"), entry.ID, err)
			}
		case "conditional":
			want := fileExists(strings.TrimPrefix(entry.DisableRule, "condition:"))
			enabled := a.systemdManifestUnitEnabled(user, entry.SystemdUnit)
			if want == enabled {
				continue
			}
			changed = true
			if checkOnly {
				continue
			}
			if want {
				if a.enableSystemdManifestUnit(user, false, entry.SystemdUnit) != ExitOK {
					return ExitFailure
				}
			} else if a.disableSystemdManifestUnit(user, false, entry.SystemdUnit) != ExitOK {
				return ExitFailure
			}
		}
	}
	if checkOnly && changed {
		return ExitFalse
	}
	return ExitOK
}

func (a *App) isSystemdGlobalUserEntry(entry serviceManifestEntry) bool {
	return entry.Scope == "user" &&
		entry.SystemdUnit != "-" &&
		strings.HasPrefix(entry.DisableRule, "preserve:/") &&
		fileExists(filepath.Join(a.cfg.SystemdUserDir, entry.SystemdUnit))
}

func (a *App) systemdManifestUnitExists(user bool, unit string) bool {
	if !user {
		return fileExists(filepath.Join(a.cfg.SystemdSystemDir, unit))
	}
	if fileExists(filepath.Join(a.cfg.SystemdUserDir, unit)) {
		return true
	}
	config := a.getenv("XDG_CONFIG_HOME")
	if config == "" {
		config = filepath.Join(a.home(), ".config")
	}
	return fileExists(filepath.Join(config, "systemd", "user", unit))
}

func (a *App) systemdManifestArgs(user bool, args ...string) []string {
	return a.systemdScopeArgs(user, args...)
}

func (a *App) systemdManifestUnitEnabled(user bool, unit string) bool {
	result := a.probe("systemctl", a.systemdManifestArgs(user, "is-enabled", "--quiet", unit)...)
	return result.Code == 0
}

func (a *App) systemdManifestShouldStartNow(user bool) bool {
	if user {
		return a.getenv("WAYLAND_DISPLAY") != ""
	}
	return isDir(a.cfg.SystemdRuntimeDir)
}

func (a *App) enableSystemdManifestUnit(user, startNow bool, unit string) int {
	args := []string{"enable"}
	if startNow {
		args = append(args, "--now")
	}
	args = append(args, unit)
	return commandExit(a.run("systemctl", a.systemdManifestArgs(user, args...)...))
}

func (a *App) disableSystemdManifestUnit(user, stopNow bool, unit string) int {
	args := []string{"disable"}
	if stopNow {
		args = append(args, "--now")
	}
	args = append(args, unit)
	return commandExit(a.run("systemctl", a.systemdManifestArgs(user, args...)...))
}

func (a *App) userServiceManifestStateDir() string {
	state := a.getenv("XDG_STATE_HOME")
	if state == "" {
		state = filepath.Join(a.home(), ".local", "state")
	}
	return filepath.Join(state, "ryoku", "service-manifest")
}

func (a *App) adoptSystemdUserBaseline(entries []serviceManifestEntry, checkOnly bool) (bool, error) {
	stateDir := a.userServiceManifestStateDir()
	if _, err := os.Stat(stateDir); err == nil {
		return false, nil
	} else if !os.IsNotExist(err) {
		return false, err
	}
	if !fileExists(filepath.Join(filepath.Dir(stateDir), "welcome-seen")) {
		return false, nil
	}
	if checkOnly {
		return true, nil
	}
	for _, entry := range entries {
		if entry.Scope != "user" || entry.Activation != "session" {
			continue
		}
		if err := writeServiceMarker(a.serviceActivationMarker(entry, true)); err != nil {
			return false, err
		}
	}
	return true, nil
}

func (a *App) serviceActivationMarker(entry serviceManifestEntry, user bool) string {
	if !user {
		if strings.HasPrefix(entry.DisableRule, "preserve:/") {
			return strings.TrimPrefix(entry.DisableRule, "preserve:")
		}
		return filepath.Join(a.cfg.ServiceStateDir, entry.ID+"-enabled")
	}
	return filepath.Join(a.userServiceManifestStateDir(), entry.ID+"-enabled")
}

func (a *App) serviceActivationRecorded(entry serviceManifestEntry, user bool) bool {
	if fileExists(a.serviceActivationMarker(entry, user)) {
		return true
	}
	return user && strings.HasPrefix(entry.DisableRule, "preserve:/") &&
		fileExists(strings.TrimPrefix(entry.DisableRule, "preserve:"))
}

func writeServiceMarker(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, nil, 0o644)
}

func (a *App) reconcileRunitSystemServices(entries []serviceManifestEntry, checkOnly bool) int {
	changed := false
	for _, entry := range entries {
		if entry.Scope != "system" || entry.RunitName == "-" {
			continue
		}
		definition := filepath.Join(a.cfg.SystemServiceDir, entry.RunitName)
		if !isDir(definition) {
			continue
		}
		link := filepath.Join(a.cfg.SystemBootDir, entry.RunitName)
		switch entry.Activation {
		case "boot":
			if exactLink(definition, link) {
				continue
			}
			changed = true
			if !checkOnly {
				if err := ensureLink(definition, link); err != nil {
					return a.failf(i18n.T("enable %s: %v"), entry.ID, err)
				}
			}
		case "enable-once":
			marker := a.serviceActivationMarker(entry, false)
			if fileExists(marker) {
				continue
			}
			changed = true
			if checkOnly {
				continue
			}
			if !exactLink(definition, link) {
				if err := ensureLink(definition, link); err != nil {
					return a.failf(i18n.T("enable %s: %v"), entry.ID, err)
				}
			}
			if err := writeServiceMarker(marker); err != nil {
				return a.failf(i18n.T("record service activation %s: %v"), entry.ID, err)
			}
		case "conditional":
			want := fileExists(strings.TrimPrefix(entry.DisableRule, "condition:"))
			enabled := exactLink(definition, link)
			if want == enabled {
				continue
			}
			changed = true
			if checkOnly {
				continue
			}
			if want {
				if err := ensureLink(definition, link); err != nil {
					return a.failf(i18n.T("enable %s: %v"), entry.ID, err)
				}
				continue
			}
			for _, path := range []string{link, filepath.Join(a.cfg.SystemLiveDir, entry.RunitName)} {
				if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
					return a.failf(i18n.T("disable %s: %v"), entry.ID, err)
				}
			}
		}
	}
	if checkOnly && changed {
		return ExitFalse
	}
	return ExitOK
}

func exactLink(target, path string) bool {
	current, err := os.Readlink(path)
	return err == nil && current == target
}

func (a *App) reconcileRunitUserServices(entries []serviceManifestEntry, checkOnly bool) int {
	roster := filepath.Join(a.userServiceDir(), ".ryoku-session-services")
	current, err := os.ReadFile(roster)
	if err != nil && !os.IsNotExist(err) {
		return a.failf(i18n.T("read runit session roster: %v"), err)
	}
	known := make(map[string]bool)
	for _, name := range strings.Fields(string(current)) {
		known[name] = true
	}
	var desired []string
	for _, entry := range entries {
		if entry.Scope != "user" ||
			entry.Activation != "session" && entry.Activation != "session-global" ||
			entry.RunitName == "-" {
			continue
		}
		service := filepath.Join(a.userServiceDir(), entry.RunitName)
		if !isDir(service) {
			continue
		}
		if entry.Activation == "session" && fileExists(filepath.Join(service, runitUserDisabledMarker)) {
			continue
		}
		desired = append(desired, entry.RunitName)
	}
	body := []byte(strings.Join(desired, "\n") + "\n")
	changed := !bytes.Equal(current, body)
	if checkOnly {
		if changed {
			return ExitFalse
		}
		return ExitOK
	}
	if changed {
		if err := sys.WriteFileAtomic(roster, string(body), 0o644); err != nil {
			return a.failf(i18n.T("write runit session roster: %v"), err)
		}
	}
	for _, name := range desired {
		if known[name] {
			continue
		}
		service := filepath.Join(a.userServiceDir(), name)
		if err := os.Remove(filepath.Join(service, "down")); err != nil && !os.IsNotExist(err) {
			return a.failf(i18n.T("unpark %s: %v"), name, err)
		}
		if isSupervised(service) {
			if result := a.run("sv", "up", service); result.Code != 0 {
				return commandExit(result)
			}
		}
	}
	return ExitOK
}
