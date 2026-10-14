package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNoDisplayDesktopEntriesIncludesNestedAndKeepsRootPrecedence(t *testing.T) {
	user := t.TempDir()
	system := t.TempDir()
	writeDesktopEntry(t, filepath.Join(user, "org.example.override.desktop"), false)
	writeDesktopEntry(t, filepath.Join(user, "vendor", "nested.desktop"), true)
	writeDesktopEntry(t, filepath.Join(system, "org.example.override.desktop"), true)
	writeDesktopEntry(t, filepath.Join(system, "org.example.hidden.desktop"), true)
	touch(t, filepath.Join(system, "not-a-desktop.txt"))

	got := noDisplayDesktopEntries([]string{user, system})
	if len(got) != 2 || got[0].ID != "vendor-nested.desktop" || got[1].ID != "org.example.hidden.desktop" {
		t.Fatalf("noDisplayDesktopEntries = %v", got)
	}
	if got[0].Name != "Bridge" || got[0].Icon != "org.example.bridge" || got[0].StartupClass != "Bridge" {
		t.Fatalf("desktop entry metadata = %#v", got[0])
	}
}

func writeDesktopEntry(t *testing.T, path string, noDisplay bool) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	body := "[Desktop Entry]\nType=Application\nName=Bridge\nIcon=org.example.bridge\nStartupWMClass=Bridge\nNoDisplay=false\n"
	if noDisplay {
		body = "[Desktop Entry]\nType=Application\nName=Bridge\nIcon=org.example.bridge\nStartupWMClass=Bridge\nNoDisplay=true\n"
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
