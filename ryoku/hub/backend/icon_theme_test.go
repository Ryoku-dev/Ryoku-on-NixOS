package main

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func writeIconTheme(t *testing.T, root, code, index string, dirs ...string) string {
	t.Helper()
	theme := filepath.Join(root, code)
	if err := os.MkdirAll(theme, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(theme, "index.theme"), []byte(index), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(filepath.Join(theme, dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return theme
}

func TestListIconThemesFiltersLabelsAndDeduplicates(t *testing.T) {
	first, second := t.TempDir(), t.TempDir()
	writeIconTheme(t, first, "papirus", "[Icon Theme]\nName=Papirus First\nDirectories=16x16/apps\n", "16x16/apps")
	writeIconTheme(t, second, "papirus", "[Icon Theme]\nName=Papirus Duplicate\nDirectories=apps\n", "apps")
	writeIconTheme(t, first, "pretty", "[Icon Theme]\nName=Pretty Icons\nScaledDirectories=scalable/apps\n", "scalable/apps")
	writeIconTheme(t, first, "cursor-only", "[Icon Theme]\nName=Pointer Only\nDirectories=cursors\n", "cursors")
	writeIconTheme(t, first, "hidden", "[Icon Theme]\nName=Hidden Icons\nHidden=TRUE\nDirectories=apps\n", "apps")
	writeIconTheme(t, first, "empty", "[Icon Theme]\nName=Missing Directory\nDirectories=apps\n")
	target := writeIconTheme(t, t.TempDir(), "linked-target", "[Icon Theme]\nName=Linked Icons\nDirectories=apps\n", "apps")
	if err := os.Symlink(target, filepath.Join(first, "linked")); err != nil {
		t.Fatal(err)
	}

	got := listIconThemesFromDirs([]string{first, second})
	want := []iconThemeOption{
		{Code: "linked", Name: "Linked Icons"},
		{Code: "papirus", Name: "Papirus First"},
		{Code: "pretty", Name: "Pretty Icons"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("listIconThemesFromDirs() = %#v, want %#v", got, want)
	}
}

func TestIconSearchDirsUseXDGOrder(t *testing.T) {
	home, dataHome := t.TempDir(), t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_DATA_HOME", dataHome)
	t.Setenv("XDG_DATA_DIRS", "/opt/one:/opt/two")
	want := []string{
		filepath.Join(dataHome, "icons"),
		filepath.Join(home, ".icons"),
		"/opt/one/icons",
		"/opt/two/icons",
	}
	if got := iconSearchDirs(); !reflect.DeepEqual(got, want) {
		t.Fatalf("iconSearchDirs() = %#v, want %#v", got, want)
	}
}

func TestParseIconThemeUsesIconThemeSection(t *testing.T) {
	path := filepath.Join(t.TempDir(), "index.theme")
	body := "Name=Wrong\n[Other]\nHidden=true\n[Icon Theme]\nName=Right Name\nHidden=false\nDirectories=apps, places\n"
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := parseIconTheme(path)
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "Right Name" || got.Hidden || !reflect.DeepEqual(got.Directories, []string{"apps", "places"}) {
		t.Fatalf("parseIconTheme() = %#v", got)
	}
}

func TestSetINIValuePreservesOtherSectionsAndKeys(t *testing.T) {
	in := []byte("# keep\n[Appearance]\nstyle=Fusion\nicon_theme=Old\ncustom_palette=true\n\n[Fonts]\ngeneral=Keep Me\n")
	got := string(setINIValue(in, "Appearance", "icon_theme", "Papirus-Dark"))
	for _, want := range []string{
		"# keep\n",
		"style=Fusion\n",
		"icon_theme=Papirus-Dark\n",
		"custom_palette=true\n",
		"[Fonts]\ngeneral=Keep Me\n",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("updated INI missing %q; got:\n%s", want, got)
		}
	}
	if strings.Contains(got, "icon_theme=Old") {
		t.Errorf("old value survived:\n%s", got)
	}

	inserted := string(setINIValue([]byte("[Settings]\ngtk-theme-name=Keep\n[Other]\nkey=value\n"), "Settings", "gtk-icon-theme-name", "Pretty"))
	if !strings.Contains(inserted, "gtk-theme-name=Keep\ngtk-icon-theme-name=Pretty\n[Other]") {
		t.Fatalf("insert did not stay inside Settings:\n%s", inserted)
	}
}

func TestApplyIconThemeWritesEveryConsumerAndState(t *testing.T) {
	home, config, data := t.TempDir(), t.TempDir(), t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", config)
	t.Setenv("XDG_DATA_HOME", data)
	t.Setenv("XDG_DATA_DIRS", "")
	writeIconTheme(t, filepath.Join(data, "icons"), "pretty", "[Icon Theme]\nName=Pretty Icons\nDirectories=apps\n", "apps")

	fixtures := map[string]string{
		filepath.Join(config, "gtk-3.0", "settings.ini"): "[Settings]\ngtk-theme-name=KeepGtk3\ngtk-icon-theme-name=Old\n",
		filepath.Join(config, "gtk-4.0", "settings.ini"): "[Settings]\ngtk-theme-name=KeepGtk4\n",
		filepath.Join(config, "qt6ct", "qt6ct.conf"):     "[Appearance]\nstyle=Fusion\nicon_theme=Old\n[Fonts]\ngeneral=KeepQt\n",
		filepath.Join(config, "kdeglobals"):              "[General]\nColorScheme=KeepKDE\n",
	}
	for path, body := range fixtures {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	oldRun := runIconCommand
	oldOut := runIconCommandOutput
	t.Cleanup(func() { runIconCommand, runIconCommandOutput = oldRun, oldOut })
	var command []string
	runIconCommand = func(name string, args ...string) error {
		command = append([]string{name}, args...)
		return nil
	}
	runIconCommandOutput = func(string, ...string) ([]byte, error) { return []byte("'Old'\n"), nil }

	if err := applyIconTheme("pretty"); err != nil {
		t.Fatal(err)
	}
	wantCommand := []string{"gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "pretty"}
	if !reflect.DeepEqual(command, wantCommand) {
		t.Fatalf("gsettings command = %#v, want %#v", command, wantCommand)
	}
	if got := storedIconTheme(); got != "pretty" {
		t.Fatalf("storedIconTheme() = %q, want pretty", got)
	}
	if got := currentIconTheme(); got != "pretty" {
		t.Fatalf("currentIconTheme() = %q, want pretty", got)
	}
	checks := map[string][]string{
		filepath.Join(config, "gtk-3.0", "settings.ini"): {"gtk-theme-name=KeepGtk3", "gtk-icon-theme-name=pretty"},
		filepath.Join(config, "gtk-4.0", "settings.ini"): {"gtk-theme-name=KeepGtk4", "gtk-icon-theme-name=pretty"},
		filepath.Join(config, "qt6ct", "qt6ct.conf"):     {"style=Fusion", "icon_theme=pretty", "general=KeepQt"},
		filepath.Join(config, "kdeglobals"):              {"ColorScheme=KeepKDE", "[Icons]", "Theme=pretty"},
	}
	for path, wants := range checks {
		body, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		for _, want := range wants {
			if !strings.Contains(string(body), want) {
				t.Errorf("%s missing %q; got:\n%s", path, want, body)
			}
		}
	}
}

func TestApplyIconThemeRejectsUnknownTheme(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	t.Setenv("XDG_DATA_DIRS", t.TempDir())
	if err := applyIconTheme("not-installed"); err == nil {
		t.Fatal("unknown theme was accepted")
	}
	if _, err := os.Stat(iconThemeStatePath()); !os.IsNotExist(err) {
		t.Fatalf("invalid selection wrote state: %v", err)
	}
}
