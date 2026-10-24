package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func init() {
	registerAfterScan(autoRecolourNewWallpapers)
}

func autoRecolourNewWallpapers(d *daemon, added []Entry) {
	if !d.settingBool("effects.autoRecolor") {
		return
	}
	theme := d.settingString("effects.autoTheme")
	if theme == "" {
		return
	}
	go d.recolourEntries(added, theme)
}

func (d *daemon) recolourEntries(added []Entry, theme string) {
	params := map[string]interface{}{"theme": theme}
	suffix := effectSuffix("theme", params)
	changed := false
	for _, e := range added {
		if e.Type != "static" || e.Path == "" || isRecolourOutput(e.Path) {
			continue
		}
		out, err := libraryPath(e.Path, suffix)
		if err != nil || fileExists(out) {
			continue
		}
		if err := renderToFile("theme", e.Path, params, out); err != nil {
			fmt.Fprintf(os.Stderr, "ryogami: auto-recolour failed for %s: %v\n", e.Name, err)
			continue
		}
		changed = true
	}
	if changed {
		d.rescan(false)
	}
}

// Skips its own output so recolouring never feeds on itself.
func isRecolourOutput(p string) bool {
	return strings.Contains(filepath.ToSlash(p), "/effects/")
}
