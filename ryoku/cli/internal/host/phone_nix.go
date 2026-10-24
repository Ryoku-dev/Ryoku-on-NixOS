package host

import (
	"encoding/json"
	"fmt"
	"os"
)

const phoneNixHint = "Phone support is managed by NixOS. Set programs.ryoku.phone.enable = true and rebuild."

func (a *App) phoneNix(action string) int {
	switch action {
	case "status", "enable", "disable", "plan-enable", "plan-disable":
	default:
		return ExitUsage
	}
	if action == "disable" {
		return ExitOK
	}
	path := a.getenv("RYOKU_NIX_PHONE_CONFIG")
	if path == "" {
		path = "/etc/ryoku/phone.json"
	}
	var config struct {
		Enabled bool `json:"enabled"`
		Webcam  bool `json:"webcam"`
	}
	body, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return a.failf("read NixOS phone configuration: %v", err)
	}
	if err == nil {
		if err := json.Unmarshal(body, &config); err != nil {
			return a.failf("read NixOS phone configuration: %v", err)
		}
	}
	if action == "enable" {
		if !config.Enabled {
			return a.failf("%s", phoneNixHint)
		}
		return ExitOK
	}
	if action == "status" {
		status := struct {
			phoneStatus
			Webcam bool `json:"webcam"`
		}{phoneStatus: phoneStatus{
			Manager: PackageManager("nix"), Installed: config.Enabled,
			Configured: config.Enabled, Supported: config.Enabled,
		}, Webcam: config.Webcam}
		if !config.Enabled {
			status.Reason = phoneNixHint
		}
		return a.phoneNixJSON(status)
	}
	return a.phoneNixJSON(struct {
		Manager  string     `json:"manager"`
		Action   string     `json:"action"`
		Packages []string   `json:"packages"`
		Commands [][]string `json:"commands"`
		Reason   string     `json:"reason"`
	}{"nix", action, []string{}, [][]string{}, phoneNixHint})
}

func (a *App) phoneNixJSON(value any) int {
	body, err := json.Marshal(value)
	if err != nil {
		return a.failf("encode NixOS phone response: %v", err)
	}
	fmt.Fprintln(a.cfg.Stdout, string(body))
	return ExitOK
}
