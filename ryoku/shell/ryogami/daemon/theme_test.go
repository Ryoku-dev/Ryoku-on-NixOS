package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSlugThemeRejectsTraversal(t *testing.T) {
	cases := map[string]string{
		"My Theme":      "My-Theme",
		"../etc/passwd": "etcpasswd",
		"a/b":           "ab",
		"  spaced  ":    "spaced",
		"weird!!name":   "weirdname",
		"__x__":         "x",
	}
	for in, want := range cases {
		if got := slugTheme(in); got != want {
			t.Errorf("slugTheme(%q)=%q want %q", in, got, want)
		}
	}
	if slugTheme("///..") != "" {
		t.Errorf("a name that is all separators must slug to empty, not %q", slugTheme("///.."))
	}
}

func TestNineFromColorsMapping(t *testing.T) {
	colors := map[string]string{
		"primary": "#112233", "onPrimary": "#ffffff",
		"surface": "#0a0a0a", "onSurface": "#eeeeee",
		"surfaceVariant": "#222222", "surfaceContainer": "#151515",
		"background": "#000000", "outline": "#888888", "tertiary": "#aa5599",
	}
	want := map[string]string{
		"primary": "#112233", "primaryText": "#ffffff",
		"surface": "#0a0a0a", "surfaceText": "#eeeeee",
		"surfaceVariant": "#222222", "surfaceContainer": "#151515",
		"background": "#000000", "outline": "#888888", "tertiary": "#aa5599",
	}
	n := nineFromColors(colors)
	for k, v := range want {
		if n[k] != v {
			t.Errorf("nineFromColors[%q]=%q want %q", k, n[k], v)
		}
	}
	partial := map[string]string{"primary": "#112233", "surface": "#0a0a0a", "secondary": "#334455"}
	np := nineFromColors(partial)
	if np["surfaceContainer"] != "#0a0a0a" {
		t.Errorf("surfaceContainer fallback=%q want surface", np["surfaceContainer"])
	}
	if np["background"] != "#0a0a0a" {
		t.Errorf("background fallback=%q want surface", np["background"])
	}
	if np["tertiary"] != "#334455" {
		t.Errorf("tertiary fallback=%q want secondary", np["tertiary"])
	}
}

func TestNineFromSw(t *testing.T) {
	sw := []string{"#101010", "#f0f0f0", "#89b4fa", "#a6e3a1", "#f5c2e7", "#f38ba8", "#6c7086"}
	n := nineFromSw(sw)
	if n["surface"] != "#101010" || n["surfaceText"] != "#f0f0f0" ||
		n["primary"] != "#89b4fa" || n["tertiary"] != "#f5c2e7" || n["outline"] != "#6c7086" {
		t.Errorf("nineFromSw mapping wrong: %v", n)
	}
	if nineFromSw([]string{"#000"}) != nil {
		t.Error("fewer than seven swatches must yield nil")
	}
}

func TestNoctaliaRoundTrip(t *testing.T) {
	roles := map[string]string{
		"primary": "#89b4fa", "primaryText": "#11111b", "surface": "#1e1e2e",
		"surfaceText": "#cdd6f4", "surfaceVariant": "#313244", "surfaceContainer": "#181825",
		"background": "#11111b", "outline": "#6c7086", "tertiary": "#f5c2e7",
	}
	block, err := noctaliaBlock(roles, true)
	if err != nil {
		t.Fatal(err)
	}
	back := nineFromBlock(block)
	for _, k := range []string{"primary", "primaryText", "surface", "surfaceText", "surfaceVariant", "outline", "tertiary"} {
		if back[k] != roles[k] {
			t.Errorf("role %q round-trip: got %q want %q", k, back[k], roles[k])
		}
	}
	if _, err := noctaliaBlock(map[string]string{"primary": "not-a-colour"}, true); err == nil {
		t.Error("a block without valid core roles must error")
	}
}

func TestSaveThemeSchemeAndDelete(t *testing.T) {
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	roles := map[string]string{
		"primary": "#89b4fa", "primaryText": "#11111b", "surface": "#1e1e2e",
		"surfaceText": "#cdd6f4", "surfaceVariant": "#313244", "surfaceContainer": "#181825",
		"background": "#11111b", "outline": "#6c7086", "tertiary": "#f5c2e7",
	}
	id := slugTheme("My Theme")
	if err := saveThemeScheme(id, "My Theme", roles, roles); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(themesDir(), id, "scheme.json")); err != nil {
		t.Fatalf("scheme.json missing: %v", err)
	}
	dark, light, ok := readSchemeBlocks(id)
	if !ok {
		t.Fatal("readSchemeBlocks failed")
	}
	if dark["mPrimary"] != "#89b4fa" {
		t.Errorf("dark mPrimary=%q", dark["mPrimary"])
	}
	if light["mError"] != "#ba1a1a" {
		t.Errorf("light block must carry a light-mode error, got %q", light["mError"])
	}
	saved := designerSavedThemes()
	if len(saved) != 1 || saved[0]["name"] != "My Theme" {
		t.Fatalf("designerSavedThemes=%v", saved)
	}

	d := &daemon{}
	if _, err := d.designerDelete(map[string]interface{}{"name": "does not exist"}); err == nil {
		t.Error("deleting an unknown theme must error")
	}
	if _, err := d.designerDelete(map[string]interface{}{"name": "My Theme"}); err != nil {
		t.Fatalf("delete real theme: %v", err)
	}
	if _, err := os.Stat(filepath.Join(themesDir(), id)); !os.IsNotExist(err) {
		t.Error("deleted theme directory must be gone")
	}
}

func TestIsStaticImageFile(t *testing.T) {
	dir := t.TempDir()
	img := filepath.Join(dir, "a.png")
	vid := filepath.Join(dir, "a.mp4")
	if err := os.WriteFile(img, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(vid, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if !isStaticImageFile(img) {
		t.Error("a png must count as a still image")
	}
	if isStaticImageFile(vid) {
		t.Error("a video must not count as a still image")
	}
	if isStaticImageFile(dir) || isStaticImageFile("") || isStaticImageFile(filepath.Join(dir, "nope.png")) {
		t.Error("a directory, empty path, or missing file must not count as a still image")
	}
}

func TestHoverPreviewAlwaysRestores(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	_ = os.MkdirAll(filepath.Dir(themeColorsPath()), 0o755)

	original := []byte(`{"primary":"#abcdef"}`)
	if err := os.WriteFile(themeColorsPath(), original, 0o644); err != nil {
		t.Fatal(err)
	}
	h := &hoverPreviewState{}
	h.saved, h.hadFile = readColorsFile()
	h.active = true
	writeColorsFile(map[string]string{"primary": "#000000"})
	h.end()
	got, _ := os.ReadFile(themeColorsPath())
	if string(got) != string(original) {
		t.Errorf("restore: got %q want %q", got, original)
	}

	_ = os.Remove(themeColorsPath())
	h2 := &hoverPreviewState{}
	h2.saved, h2.hadFile = readColorsFile()
	h2.active = true
	writeColorsFile(map[string]string{"primary": "#111111"})
	h2.end()
	if _, err := os.Stat(themeColorsPath()); !os.IsNotExist(err) {
		t.Error("with no prior palette, end must leave no colours file")
	}
}
