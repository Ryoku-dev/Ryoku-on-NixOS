package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
)

// An allowlist: roster entries that are not user-facing apps stay out of the tab.
var appThemeNames = map[string]string{
	"btop":      "btop",
	"qt":        "Qt apps",
	"gtk":       "GTK apps",
	"discord":   "Discord",
	"obs":       "OBS Studio",
	"zed":       "Zed",
	"heroic":    "Heroic",
	"telegram":  "Telegram",
	"steam":     "Steam",
	"kitty":     "Kitty",
	"cava":      "Cava",
	"fish":      "Fish",
	"yazi":      "Yazi",
	"ghostty":   "Ghostty",
	"micro":     "Micro",
	"papirus":   "Papirus icons",
	"obsidian":  "Obsidian",
	"zathura":   "Zathura",
	"alacritty": "Alacritty",
	"tmux":      "tmux",
	"sidra":     "Sidra",
	"ryotunes":  "RyoTunes",
}

var appThemeProbe = map[string]string{
	"btop":      "btop",
	"discord":   "discord",
	"obs":       "obs",
	"zed":       "zed",
	"heroic":    "heroic",
	"telegram":  "telegram-desktop",
	"steam":     "steam",
	"kitty":     "kitty",
	"cava":      "cava",
	"fish":      "fish",
	"yazi":      "yazi",
	"ghostty":   "ghostty",
	"micro":     "micro",
	"obsidian":  "obsidian",
	"zathura":   "zathura",
	"alacritty": "alacritty",
	"tmux":      "tmux",
	"ryotunes":  "ryotunes",
}

func hubMatugenTemplates() map[string]bool {
	out, err := exec.Command("ryoku-hub", "desktop", "matugen", "get").Output()
	if err != nil {
		return nil
	}
	var cfg struct {
		Templates map[string]bool `json:"templates"`
	}
	if json.Unmarshal(out, &cfg) != nil {
		return nil
	}
	return cfg.Templates
}

func appThemeStatus(id string) string {
	bin, probed := appThemeProbe[id]
	if !probed {
		return "available"
	}
	if _, err := exec.LookPath(bin); err == nil {
		return "available"
	}
	return "missing"
}

func (d *daemon) themeAppsResult() map[string]interface{} {
	roster := hubMatugenTemplates()
	rows := make([]map[string]interface{}, 0, len(appThemeNames))
	for id, name := range appThemeNames {
		enabled, present := roster[id]
		if !present {
			continue
		}
		rows = append(rows, map[string]interface{}{
			"id":      id,
			"name":    name,
			"enabled": enabled,
			"status":  appThemeStatus(id),
		})
	}
	sort.Slice(rows, func(i, j int) bool {
		return rows[i]["name"].(string) < rows[j]["name"].(string)
	})
	return map[string]interface{}{"apps": rows}
}

func setAppTheme(id string, enabled bool) error {
	if _, known := appThemeNames[id]; !known {
		return fmt.Errorf("unknown app theme %q", id)
	}
	payload, _ := json.Marshal(map[string]interface{}{
		"templates": map[string]bool{id: enabled},
	})
	if err := exec.Command("ryoku-hub", "desktop", "matugen", "set", string(payload)).Run(); err != nil {
		return fmt.Errorf("app theme write: %w", err)
	}
	return nil
}

func init() {
	registerAction("RefreshAppThemes", func(d *daemon, _ map[string]interface{}) (interface{}, error) {
		d.broadcast("ryogami.theme.apps.changed", map[string]interface{}{})
		return d.themeAppsResult(), nil
	})
	registerAction("SetAppTheme", func(d *daemon, args map[string]interface{}) (interface{}, error) {
		id := strParam(args, "id", "")
		if id == "" {
			return nil, fmt.Errorf("SetAppTheme requires an id")
		}
		if err := setAppTheme(id, boolParam(args, "enabled", false)); err != nil {
			return nil, err
		}
		d.broadcast("ryogami.theme.apps.changed", map[string]interface{}{})
		return map[string]interface{}{"ok": true}, nil
	})
}
