package host

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	i18n "ryoku-i18n"
)

const fingerprintPAMLine = "auth        sufficient    pam_fprintd_grosshack.so"

var fingerprintPAMTargets = []string{"sudo", "sddm", "polkit-1"}

type fingerprintStatus struct {
	Supported bool            `json:"supported"`
	Reason    string          `json:"reason,omitempty"`
	Targets   map[string]bool `json:"targets"`
}

func (a *App) Auth(args []string) int {
	if len(args) < 2 || args[0] != "fingerprint" {
		return ExitUsage
	}
	switch args[1] {
	case "status":
		if len(args) != 2 {
			return ExitUsage
		}
		return a.fingerprintStatus()
	case "set":
		if len(args) != 4 || !fingerprintTarget(args[2]) || (args[3] != "on" && args[3] != "off") {
			return ExitUsage
		}
		if a.cfg.UID != 0 {
			return commandExit(a.run("pkexec", "ryoku-host", "auth", "fingerprint", "set", args[2], args[3]))
		}
		return a.setFingerprintPAM(args[2], args[3] == "on")
	default:
		return ExitUsage
	}
}

func (a *App) fingerprintStatus() int {
	status := fingerprintStatus{Supported: a.fingerprintModulePresent(), Targets: map[string]bool{}}
	if !status.Supported {
		status.Reason = i18n.T("Fingerprint authentication integration is not installed on this edition.")
	}
	for _, target := range fingerprintPAMTargets {
		body, err := os.ReadFile(filepath.Join(a.cfg.PAMDir, target))
		status.Targets[target] = err == nil && strings.Contains(string(body), "pam_fprintd_grosshack")
	}
	if err := json.NewEncoder(a.cfg.Stdout).Encode(status); err != nil {
		return a.failf(i18n.T("encode fingerprint authentication status: %v"), err)
	}
	return ExitOK
}

func (a *App) setFingerprintPAM(target string, enabled bool) int {
	if !a.fingerprintModulePresent() {
		return a.failf("%s", i18n.T("Fingerprint authentication integration is not installed on this edition."))
	}
	path := filepath.Join(a.cfg.PAMDir, target)
	body, err := os.ReadFile(path)
	if err != nil {
		return a.failf(i18n.T("read %s: %v"), path, err)
	}
	info, err := os.Stat(path)
	if err != nil {
		return a.failf(i18n.T("inspect %s: %v"), path, err)
	}
	if err := os.WriteFile(path+".ryoku-fp-bak", body, info.Mode().Perm()); err != nil {
		return a.failf(i18n.T("back up %s: %v"), path, err)
	}

	lines := strings.Split(strings.TrimSuffix(string(body), "\n"), "\n")
	filtered := make([]string, 0, len(lines)+1)
	if enabled {
		filtered = append(filtered, fingerprintPAMLine)
	}
	for _, line := range lines {
		if !strings.Contains(line, "pam_fprintd_grosshack") {
			filtered = append(filtered, line)
		}
	}
	if err := os.WriteFile(path, []byte(strings.Join(filtered, "\n")+"\n"), info.Mode().Perm()); err != nil {
		return a.failf(i18n.T("write %s: %v"), path, err)
	}
	fmt.Fprintln(a.cfg.Stdout, target)
	return ExitOK
}

func (a *App) fingerprintModulePresent() bool {
	for _, path := range a.cfg.PAMModulePaths {
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return true
		}
	}
	return false
}

func fingerprintTarget(target string) bool {
	for _, candidate := range fingerprintPAMTargets {
		if target == candidate {
			return true
		}
	}
	return false
}
