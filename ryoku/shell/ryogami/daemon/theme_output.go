package main

import (
	"encoding/json"
	"os"
	"strings"
)

// The shell samples the wallpaper the daemon records as current, so pinning an output swaps that record.

var themeOutputForState func(state map[string]map[string]interface{}) string

func init() {
	themeOutputForState = func(state map[string]map[string]interface{}) string {
		src := themeOutputSetting()
		if src == "" {
			return ""
		}
		entry, ok := state[src]
		if !ok {
			return ""
		}
		path, _ := entry["path"].(string)
		return path
	}
}

func themeOutputSetting() string {
	b, err := os.ReadFile(configPath())
	if err != nil {
		return ""
	}
	var m map[string]interface{}
	if json.Unmarshal(b, &m) != nil {
		return ""
	}
	disp, ok := m["display"].(map[string]interface{})
	if !ok {
		return ""
	}
	v, _ := disp["themeOutput"].(string)
	return strings.TrimSpace(v)
}
