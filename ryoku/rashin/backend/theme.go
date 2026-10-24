package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

// The dashboard is a Ryoku surface, so it resolves its colours the way every
// Ryoku app does (ryoku/ui/Singletons/Tokens.qml): a named scheme in shell.json
// (themePalette) wins, then the live wallpaper palette in colors.json while
// theme.json's followWallpaper is not false, then the signature default. A role
// that is missing or empty falls through to the next layer, so a colors.json
// caught mid-write never paints the page black.

// themeRoles are the Material roles the dashboard paints with, and the
// signature default each one falls back to (Tokens.qml's defaults).
var themeRoles = []struct{ key, base string }{
	{"surface", "#000000"},
	{"surfaceContainerLow", "#0a0a0a"},
	{"onSurface", "#cdc4ba"},
	{"onSurfaceVariant", "#b0a9a0"},
	{"inverseSurface", "#cdc4ba"},
	{"inverseOnSurface", "#000000"},
	{"primary", "#e2342a"},
}

// Theme is what the dashboard needs to wear the desktop's look.
type Theme struct {
	Roles        map[string]string `json:"roles"`
	Source       string            `json:"source"` // "scheme", "wallpaper", or "default"
	ReduceMotion bool              `json:"reduceMotion"`
}

func cacheHome() string {
	if d := os.Getenv("XDG_CACHE_HOME"); d != "" {
		return d
	}
	return filepath.Join(home(), ".cache")
}

func stateHome() string {
	if d := os.Getenv("XDG_STATE_HOME"); d != "" {
		return d
	}
	return filepath.Join(home(), ".local", "state")
}

func readJSONObject(path string) map[string]any {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var m map[string]any
	if json.Unmarshal(b, &m) != nil {
		return nil
	}
	return m
}

func usableHex(v any) (string, bool) {
	s, ok := v.(string)
	return s, ok && strings.HasPrefix(s, "#") && (len(s) == 7 || len(s) == 9)
}

// ThemeNow resolves the dashboard palette from the same three files the
// desktop reads.
func ThemeNow() Theme {
	shell := readJSONObject(filepath.Join(configHome(), "ryoku", "shell.json"))
	named, _ := shell["themePalette"].(map[string]any)

	follow := true
	if t := readJSONObject(filepath.Join(configHome(), "ryoku", "theme.json")); t != nil {
		if f, ok := t["followWallpaper"].(bool); ok {
			follow = f
		}
	}
	var wall map[string]any
	if follow {
		wall = readJSONObject(filepath.Join(cacheHome(), "ryoku", "colors.json"))
	}

	th := Theme{Roles: make(map[string]string, len(themeRoles)), Source: "default"}
	for _, r := range themeRoles {
		if v, ok := usableHex(named[r.key]); ok {
			th.Roles[r.key] = v
			th.Source = "scheme"
			continue
		}
		if v, ok := usableHex(wall[r.key]); ok {
			th.Roles[r.key] = v
			if th.Source == "default" {
				th.Source = "wallpaper"
			}
			continue
		}
		th.Roles[r.key] = r.base
	}
	if theme, ok := shell["theme"].(map[string]any); ok {
		if m, ok := theme["motion"].(map[string]any); ok {
			th.ReduceMotion, _ = m["reduce"].(bool)
		}
	}
	return th
}

// wallpaperKinds are the files the wallpaper endpoint will hand the page; the
// state file names whatever ryogami painted, and anything else is refused.
var wallpaperKinds = map[string]string{
	".jpg": "image", ".jpeg": "image", ".png": "image", ".webp": "image", ".gif": "image",
	".mp4": "video", ".webm": "video", ".mkv": "video", ".mov": "video",
}

// CurrentWallpaper reads the wallpaper ryogami reports as on screen
// (~/.local/state/ryoku-wallpaper, the file the overview backdrop and rice
// capture also read) and reports its path and kind, or ok=false when there is
// none or it is not a file the page can show.
func CurrentWallpaper() (path, kind string, ok bool) {
	b, err := os.ReadFile(filepath.Join(stateHome(), "ryoku-wallpaper"))
	if err != nil {
		return "", "", false
	}
	path = strings.TrimSpace(string(b))
	kind, known := wallpaperKinds[strings.ToLower(filepath.Ext(path))]
	if path == "" || !known {
		return "", "", false
	}
	if st, err := os.Stat(path); err != nil || !st.Mode().IsRegular() {
		return "", "", false
	}
	return path, kind, true
}
