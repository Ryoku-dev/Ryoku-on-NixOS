package main

import (
	"os"
	"path/filepath"
	"testing"
)

// The mirror follows the shipped set exactly: a changed page is rewritten, a
// page that stopped shipping disappears, and a box without a shipped wiki is
// left alone rather than failing EnsureVault.
func TestSyncWikiTracksShippedPages(t *testing.T) {
	src := t.TempDir()
	vault := t.TempDir()
	t.Setenv("RYOKU_RASHIN_WIKI", src)
	write := func(dir, name, body string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(src, "README.md", "# Wiki\n")
	write(src, "niri-kdl.md", "# niri\n")
	if err := syncWiki(vault); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(vault, "wiki", "niri-kdl.md"))
	if err != nil || string(got) != "# niri\n" {
		t.Fatalf("mirror missed a page: %q %v", got, err)
	}

	write(src, "niri-kdl.md", "# niri, revised\n")
	if err := os.Remove(filepath.Join(src, "README.md")); err != nil {
		t.Fatal(err)
	}
	write(src, "README.md", "# Wiki 2\n")
	write(vault+"/wiki", "stale.md", "# gone upstream\n")
	if err := syncWiki(vault); err != nil {
		t.Fatal(err)
	}
	got, _ = os.ReadFile(filepath.Join(vault, "wiki", "niri-kdl.md"))
	if string(got) != "# niri, revised\n" {
		t.Fatalf("changed page not rewritten: %q", got)
	}
	if _, err := os.Stat(filepath.Join(vault, "wiki", "stale.md")); !os.IsNotExist(err) {
		t.Fatal("a page that no longer ships must leave the mirror")
	}

	t.Setenv("RYOKU_RASHIN_WIKI", filepath.Join(t.TempDir(), "absent"))
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	if err := syncWiki(vault); err != nil {
		t.Fatalf("no shipped wiki must not fail: %v", err)
	}
	if _, err := os.Stat(filepath.Join(vault, "wiki", "niri-kdl.md")); err != nil {
		t.Fatal("without a source the mirror is left as it was")
	}
}
