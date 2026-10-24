package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// The two elevation roles have no field in this format and are re-derived on read.
func noctaliaBlock(r map[string]string, dark bool) (map[string]string, error) {
	primary := r["primary"]
	surface := r["surface"]
	onSurface := r["surfaceText"]
	if !themeIsHex(primary) || !themeIsHex(surface) || !themeIsHex(onSurface) {
		return nil, fmt.Errorf("a theme needs valid primary, surface and panel-text colours")
	}
	onPrimary := firstHex(r["primaryText"], themeContrastInk(primary))
	second := firstHex(r["tertiary"], primary)
	variant := firstHex(r["surfaceVariant"], themeMixHex(surface, onSurface, 0.16))
	outline := firstHex(r["outline"], themeMixHex(surface, onSurface, 0.45))
	errCol, onErr := "#ffb4ab", "#690005"
	if !dark {
		errCol, onErr = "#ba1a1a", "#ffffff"
	}
	return map[string]string{
		"mPrimary":          primary,
		"mOnPrimary":        onPrimary,
		"mSecondary":        second,
		"mOnSecondary":      themeContrastInk(second),
		"mTertiary":         second,
		"mOnTertiary":       themeContrastInk(second),
		"mError":            errCol,
		"mOnError":          onErr,
		"mSurface":          surface,
		"mOnSurface":        onSurface,
		"mSurfaceVariant":   variant,
		"mOnSurfaceVariant": themeMixHex(onSurface, surface, 0.25),
		"mOutline":          outline,
		"mShadow":           "#000000",
	}, nil
}

func nineFromBlock(b map[string]string) map[string]string {
	surface := b["mSurface"]
	onSurface := b["mOnSurface"]
	return map[string]string{
		"primary":          b["mPrimary"],
		"primaryText":      firstHex(b["mOnPrimary"], themeContrastInk(b["mPrimary"])),
		"surface":          surface,
		"surfaceText":      onSurface,
		"surfaceVariant":   firstHex(b["mSurfaceVariant"], themeMixHex(surface, onSurface, 0.16)),
		"surfaceContainer": themeMixHex(surface, onSurface, 0.08),
		"background":       surface,
		"outline":          firstHex(b["mOutline"], themeMixHex(surface, onSurface, 0.45)),
		"tertiary":         firstHex(b["mTertiary"], b["mSecondary"], b["mPrimary"]),
	}
}

func saveThemeScheme(id, label string, dark, light map[string]string) error {
	if len(light) == 0 {
		light = dark
	}
	if len(dark) == 0 {
		dark = light
	}
	darkBlock, err := noctaliaBlock(dark, true)
	if err != nil {
		return err
	}
	lightBlock, err := noctaliaBlock(light, false)
	if err != nil {
		return err
	}
	dir := filepath.Join(themesDir(), id)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	scheme := map[string]interface{}{"dark": darkBlock, "light": lightBlock}
	if err := themeWriteFile(filepath.Join(dir, "scheme.json"), scheme); err != nil {
		return err
	}
	return themeWriteFile(filepath.Join(dir, "meta.json"), map[string]string{"label": label, "provider": "designer"})
}

// Drops anything that could escape the themes directory.
func slugTheme(name string) string {
	var b strings.Builder
	for _, r := range strings.TrimSpace(name) {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
			b.WriteRune(r)
		case r == ' ':
			b.WriteRune('-')
		}
	}
	return strings.Trim(b.String(), "-_")
}

// Built-ins and dynamic variants shadow library schemes, so saving over one would vanish.
func builtinThemeIDs() map[string]bool {
	taken := map[string]bool{}
	out, err := exec.Command("ryoku-shell", "theme", "catalog").Output()
	if err != nil {
		return taken
	}
	var cards []struct {
		ID       string `json:"id"`
		Provider string `json:"provider"`
	}
	if json.Unmarshal(out, &cards) != nil {
		return taken
	}
	for _, c := range cards {
		if c.Provider == "" {
			taken[c.ID] = true
		}
	}
	return taken
}

func designerSavedThemes() []map[string]interface{} {
	entries, err := os.ReadDir(themesDir())
	if err != nil {
		return nil
	}
	out := []map[string]interface{}{}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(themesDir(), e.Name())
		var meta struct {
			Label    string `json:"label"`
			Provider string `json:"provider"`
		}
		if b, err := os.ReadFile(filepath.Join(dir, "meta.json")); err == nil {
			_ = json.Unmarshal(b, &meta)
		}
		if meta.Provider != "designer" {
			continue
		}
		dark, light, ok := readSchemeBlocks(e.Name())
		if !ok {
			continue
		}
		label := meta.Label
		if label == "" {
			label = e.Name()
		}
		out = append(out, map[string]interface{}{
			"name":  label,
			"dark":  nineFromBlock(dark),
			"light": nineFromBlock(light),
		})
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i]["name"].(string) < out[j]["name"].(string)
	})
	return out
}

func readSchemeBlocks(id string) (dark, light map[string]string, ok bool) {
	raw, err := os.ReadFile(filepath.Join(themesDir(), id, "scheme.json"))
	if err != nil {
		return nil, nil, false
	}
	var scheme struct {
		Dark  map[string]string `json:"dark"`
		Light map[string]string `json:"light"`
	}
	if json.Unmarshal(raw, &scheme) != nil {
		return nil, nil, false
	}
	dark, light = scheme.Dark, scheme.Light
	if dark == nil {
		dark = light
	}
	if light == nil {
		light = dark
	}
	if dark == nil {
		return nil, nil, false
	}
	return dark, light, true
}

func liveNine() map[string]string {
	colors := map[string]string{}
	if b, err := os.ReadFile(themeColorsPath()); err == nil {
		_ = json.Unmarshal(b, &colors)
	}
	return nineFromColors(colors)
}

func (d *daemon) designerLoad(p map[string]interface{}) map[string]interface{} {
	name := strings.TrimSpace(strParam(p, "name", ""))
	if name == "" {
		return map[string]interface{}{
			"saved":   designerSavedThemes(),
			"current": liveNine(),
		}
	}
	id := slugTheme(name)
	if dark, light, ok := readSchemeBlocks(id); ok {
		return map[string]interface{}{
			"name":  name,
			"dark":  nineFromBlock(dark),
			"light": nineFromBlock(light),
		}
	}
	if nine, ok := nineFromCatalog(name); ok {
		return map[string]interface{}{"name": name, "dark": nine, "light": nine}
	}
	live := liveNine()
	return map[string]interface{}{"name": name, "dark": live, "light": live}
}

func nineFromCatalog(name string) (map[string]string, bool) {
	out, err := exec.Command("ryoku-shell", "theme", "catalog").Output()
	if err != nil {
		return nil, false
	}
	var cards []struct {
		ID    string   `json:"id"`
		Label string   `json:"label"`
		Sw    []string `json:"sw"`
	}
	if json.Unmarshal(out, &cards) != nil {
		return nil, false
	}
	for _, c := range cards {
		if (c.ID == name || c.Label == name) && len(c.Sw) >= 7 {
			if nine := nineFromSw(c.Sw); nine != nil {
				return nine, true
			}
		}
	}
	return nil, false
}

func rolesArg(p map[string]interface{}, key string) map[string]string {
	m, _ := p[key].(map[string]interface{})
	out := map[string]string{}
	for k, v := range m {
		if s, ok := v.(string); ok {
			out[k] = s
		}
	}
	return out
}

func (d *daemon) designerSave(p map[string]interface{}) (map[string]interface{}, error) {
	name := strings.TrimSpace(strParam(p, "name", ""))
	if name == "" {
		return nil, fmt.Errorf("a theme name is required")
	}
	id := slugTheme(name)
	if id == "" {
		return nil, fmt.Errorf("theme name %q has no usable characters", name)
	}
	if builtinThemeIDs()[id] {
		return nil, fmt.Errorf("%q is a built-in theme name; choose another", name)
	}
	dark := rolesArg(p, "dark")
	light := rolesArg(p, "light")
	if len(dark) == 0 {
		dark = rolesArg(p, "roles")
	}
	if err := saveThemeScheme(id, name, dark, light); err != nil {
		return nil, err
	}
	return map[string]interface{}{"id": id, "name": name}, nil
}

func (d *daemon) designerDelete(p map[string]interface{}) (map[string]interface{}, error) {
	id := slugTheme(strParam(p, "name", ""))
	if id == "" {
		return nil, fmt.Errorf("a theme name is required")
	}
	dir := filepath.Join(themesDir(), id)
	if _, err := os.Stat(filepath.Join(dir, "scheme.json")); err != nil {
		return nil, fmt.Errorf("no saved theme %q", id)
	}
	if err := os.RemoveAll(dir); err != nil {
		return nil, err
	}
	return map[string]interface{}{"ok": true, "id": id}, nil
}
