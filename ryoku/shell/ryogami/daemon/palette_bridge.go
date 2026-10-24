package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const defaultPaletteBridgeSource = "/usr/share/ryoku/palette-bridge"

func (d *daemon) paletteBridgeSource() string {
	src := strings.TrimSpace(d.settingString("paletteBridgeSource"))
	if src == "" {
		return defaultPaletteBridgeSource
	}
	return src
}

func hubPaletteBridge(args ...string) (string, error) {
	full := append([]string{"palette-bridge"}, args...)
	out, err := exec.Command("ryoku-hub", full...).CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		return "", fmt.Errorf("palette bridge: %s", msg)
	}
	return strings.TrimSpace(string(out)), nil
}

func init() {
	registerAction("PaletteBridgeSetup", func(d *daemon, _ map[string]interface{}) (interface{}, error) {
		if _, err := hubPaletteBridge("install", d.paletteBridgeSource()); err != nil {
			return nil, err
		}
		if _, err := hubPaletteBridge("service", "enable"); err != nil {
			return nil, err
		}
		return map[string]interface{}{"ok": true, "message": "Palette bridge service installed and enabled"}, nil
	})

	for id, verb := range map[string]string{
		"PaletteBridgeEnable": "enable", "PaletteBridgeDisable": "disable",
		"PaletteBridgeRestart": "restart", "PaletteBridgeRemove": "disable",
	} {
		registerAction(id, func(d *daemon, _ map[string]interface{}) (interface{}, error) {
			out, err := hubPaletteBridge("service", verb)
			if err != nil {
				return nil, err
			}
			return map[string]interface{}{"ok": true, "message": "Palette bridge service: " + verb, "output": out}, nil
		})
	}
	registerAction("PaletteBridgeStatus", func(d *daemon, _ map[string]interface{}) (interface{}, error) {
		out, err := hubPaletteBridge("status", d.paletteBridgeSource())
		if err != nil {
			return nil, err
		}
		var status map[string]interface{}
		if err := json.Unmarshal([]byte(out), &status); err != nil || status == nil {
			return nil, fmt.Errorf("palette bridge: invalid status response")
		}
		status["message"] = fmt.Sprintf("Palette bridge: enabled=%v, active=%v, healthy=%v", status["enabled"], status["active"], status["healthy"])
		return status, nil
	})
	registerAction("PaletteBridgeDoctor", func(d *daemon, _ map[string]interface{}) (interface{}, error) {
		out, err := hubPaletteBridge("doctor", d.paletteBridgeSource())
		if err != nil {
			return nil, err
		}
		return map[string]interface{}{"ok": true, "message": out}, nil
	})
	for app, name := range map[string]string{"spotify": "Spotify", "zen": "Zen", "vesktop": "Vesktop"} {
		for verb, suffix := range map[string]string{"install": "Setup", "remove": "Remove"} {
			registerAction("PaletteBridge"+name+suffix, func(d *daemon, _ map[string]interface{}) (interface{}, error) {
				out, err := hubPaletteBridge("integration", verb, app, d.paletteBridgeSource())
				if err != nil {
					return nil, err
				}
				return map[string]interface{}{"ok": true, "message": "Palette bridge " + app + ": " + verb, "output": out}, nil
			})
		}
	}

	registerAvailability("paletteBridge", func(d *daemon) bool {
		if _, err := exec.LookPath("ryoku-hub"); err != nil {
			return false
		}
		if _, err := exec.LookPath("ryoku-palette-bridge"); err != nil {
			return false
		}
		for _, name := range []string{"install.sh", "install-integrations.sh", "remove-integrations.sh"} {
			info, err := os.Stat(filepath.Join(d.paletteBridgeSource(), name))
			if err != nil || info.IsDir() {
				return false
			}
		}
		return true
	})
}
