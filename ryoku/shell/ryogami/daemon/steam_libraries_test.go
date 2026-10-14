package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestLibraryFolderPaths(t *testing.T) {
	current := `// written by Steam
"libraryfolders"
{
	"10"
	{
		"path"		"/mnt/ten"
	}
	"0"
	{
		"path"		"/home/tester/.local/share/Steam"
		"label"		""
		"apps"
		{
			"228980"		"417436160"
		}
	}
	"2"
	{
		"path"		"/mnt/Games \"Fast\"\\Steam"
		"apps"
		{
			"431960"		"3018522051"
		}
	}
	"3"
	{
		"path"		"relative/library"
	}
}`
	doc, err := parseVDF([]byte(current))
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"/home/tester/.local/share/Steam", `/mnt/Games "Fast"\Steam`, "/mnt/ten"}
	if got := libraryFolderPaths(doc); !reflect.DeepEqual(got, want) {
		t.Fatalf("current format: got %q want %q", got, want)
	}

	legacy := `"LibraryFolders"
{
	"TimeNextStatsReport"	"1700000000"
	"ContentStatsID"	"-123"
	"1"	"/mnt/old"
}`
	doc, err = parseVDF([]byte(legacy))
	if err != nil {
		t.Fatal(err)
	}
	if got := libraryFolderPaths(doc); !reflect.DeepEqual(got, []string{"/mnt/old"}) {
		t.Fatalf("legacy format: got %q", got)
	}

	for _, broken := range []string{`"libraryfolders" { "0" { "path" "/x" }`, `"libraryfolders" { "0" "/x`, `}`} {
		if _, err := parseVDF([]byte(broken)); err == nil {
			t.Fatalf("%q parsed without an error", broken)
		}
	}
}

func TestWorkshopFollowsWallpaperEngineLibrary(t *testing.T) {
	d := newSettingsDaemon(t)
	w := &workshopLib{d: d}
	homeDir := t.TempDir()
	t.Setenv("HOME", homeDir)
	root := filepath.Join(homeDir, ".local", "share", "Steam")
	second, third := t.TempDir(), t.TempDir()
	mkdir := func(parts ...string) string {
		t.Helper()
		dir := filepath.Join(parts...)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	writeFolders := func(libs ...string) {
		t.Helper()
		body := "\"libraryfolders\"\n{\n"
		for i, lib := range libs {
			body += "\t\"" + string(rune('0'+i)) + "\"\n\t{\n\t\t\"path\"\t\t\"" + lib + "\"\n\t}\n"
		}
		if err := os.WriteFile(filepath.Join(root, "steamapps", "libraryfolders.vdf"), []byte(body+"}\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	content := func(lib string) string {
		return filepath.Join(lib, "steamapps", "workshop", "content", workshopAppID)
	}
	mkdir(root, "steamapps")

	if got := w.workshopDir(); got != content(root) {
		t.Fatalf("lone library: got %q", got)
	}
	if got := w.weAssetsDir(); got != "" {
		t.Fatalf("no install: assets %q", got)
	}

	writeFolders(root, second, third)
	mkdir(content(third))
	if got := w.workshopDir(); got != content(third) {
		t.Fatalf("downloads without an install: got %q", got)
	}

	touch(t, filepath.Join(mkdir(second, "steamapps"), "appmanifest_"+workshopAppID+".acf"))
	assets := mkdir(second, "steamapps", "common", "wallpaper_engine", "assets")
	if got := w.workshopDir(); got != content(second) {
		t.Fatalf("installed library: got %q", got)
	}
	if got := w.weAssetsDir(); got != assets {
		t.Fatalf("installed assets: got %q want %q", got, assets)
	}

	writeFolders(root, third)
	if got := w.workshopDir(); got != content(third) {
		t.Fatalf("library removed from Steam: got %q", got)
	}

	custom := mkdir(homeDir, "we-assets")
	if err := d.persistSetting("paths.steamWeAssets", custom); err != nil {
		t.Fatal(err)
	}
	if got := w.weAssetsDir(); got != custom {
		t.Fatalf("configured assets: got %q want %q", got, custom)
	}
}
