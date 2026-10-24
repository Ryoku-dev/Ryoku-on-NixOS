package main

import (
	"os"
	"path/filepath"
	"strings"
)

// Under the default cache dir so the shell finds it without knowing a paths.cache override.
func overviewBackdropDir() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		base = filepath.Join(home(), ".cache")
	}
	return filepath.Join(base, "ryogami", "overview-backdrop")
}

func overviewBackdropStatePath() string {
	return filepath.Join(overviewBackdropDir(), "state.json")
}

var backdropImageExt = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".webp": true,
	".bmp": true, ".gif": true, ".tiff": true, ".tif": true, ".avif": true,
}

func isStaticImageFile(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return false
	}
	return backdropImageExt[strings.ToLower(filepath.Ext(path))]
}

// Auto-theme recolours only a pinned still; a followed wallpaper, video or scene keeps its colours.
func (d *daemon) backdropResolve() map[string]interface{} {
	enabled := d.settingBool("overviewBackdrop.enabled")
	auto := d.settingBool("overviewBackdrop.autoTheme")
	follow := d.settingBool("overviewBackdrop.followWallpaper")
	path := d.settingString("overviewBackdrop.path")
	theme := d.settingString("overviewBackdrop.theme")

	themed := ""
	reason := ""
	switch {
	case !enabled:
		reason = "disabled"
	case !auto:
		reason = "auto-theme off"
	case follow:
		reason = "follows wallpaper"
	case !isStaticImageFile(path):
		reason = "not a still image"
	case !backdropThemeValid(theme):
		reason = "no theme"
	default:
		if out, err := d.renderThemedBackdrop(path, theme); err == nil {
			themed = out
		} else {
			reason = err.Error()
		}
	}

	writeBackdropState(themed)
	res := map[string]interface{}{"enabled": enabled, "autoTheme": auto, "themed": themed != ""}
	if themed == "" && reason != "" {
		res["reason"] = reason
	}
	return res
}

func backdropThemeValid(name string) bool {
	if name == "" {
		return false
	}
	for _, n := range themeNames() {
		if n == name {
			return true
		}
	}
	return false
}

func (d *daemon) renderThemedBackdrop(path, theme string) (string, error) {
	if err := os.MkdirAll(overviewBackdropDir(), 0o755); err != nil {
		return "", err
	}
	out := filepath.Join(overviewBackdropDir(), "themed.png")
	if err := renderToFile("theme", path, map[string]interface{}{"theme": theme}, out); err != nil {
		return "", err
	}
	return out, nil
}

func writeBackdropState(themed string) {
	_ = os.MkdirAll(overviewBackdropDir(), 0o755)
	_ = themeWriteFile(overviewBackdropStatePath(), map[string]string{"themedPath": themed})
}

func init() {
	watchSetting("overviewBackdrop.", func(d *daemon, _ string, _ interface{}) {
		d.backdropResolve()
	})
	registerAction("RefreshBackdrop", func(d *daemon, _ map[string]interface{}) (interface{}, error) {
		return d.backdropResolve(), nil
	})
	onStart(func(d *daemon) { d.backdropResolve() })
}
