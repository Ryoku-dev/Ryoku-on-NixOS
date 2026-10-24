package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLanesDiffer(t *testing.T) {
	home := t.TempDir()
	vault := filepath.Join(home, "vault")
	t.Setenv("HOME", home)
	t.Setenv("RYOKU_RASHIN_VAULT", vault)
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, "config"))
	t.Setenv("RYOKU_CONFIG_BASE", filepath.Join(home, "packaged-config-absent"))
	r, c, a := ryokuLane(), chatLane(), askLane()
	if r.Cwd != VaultDir() {
		t.Fatalf("ryoku lane cwd = %q, want the vault %q", r.Cwd, VaultDir())
	}
	if c.Cwd == r.Cwd || a.Cwd == r.Cwd || c.Cwd == a.Cwd {
		t.Fatalf("lane cwd collision: ryoku=%q chat=%q ask=%q", r.Cwd, c.Cwd, a.Cwd)
	}
	if r.ownsSession(SessionMeta{Cwd: a.Cwd}) {
		t.Fatal("Agent lane must not own an Ask session")
	}
	if r.ReadOnly || c.ReadOnly || !a.ReadOnly {
		t.Fatalf("only Ask must be read-only: ryoku=%v chat=%v ask=%v", r.ReadOnly, c.ReadOnly, a.ReadOnly)
	}
	if r.Intro() == "" || a.Intro() == "" {
		t.Fatal("Agent and Ask first turns carry the Needle identity")
	}
	if c.Intro() != "" {
		t.Fatalf("chat lane first turn must add nothing, got %q", c.Intro())
	}
}

func TestPrepareAskLaneReplacesContextWithVaultSymlink(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HOME", root)
	t.Setenv("RYOKU_CONFIG_BASE", filepath.Join(root, "packaged-config-absent"))
	vault := filepath.Join(root, "vault")
	askDir := filepath.Join(root, "ask")
	t.Setenv("RYOKU_RASHIN_VAULT", vault)
	t.Setenv("RYOKU_RASHIN_ASK_DIR", askDir)
	if err := os.MkdirAll(vault, 0o700); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(vault, "AGENTS.md")
	if err := os.WriteFile(target, []byte("vault"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(askDir, 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(askDir, "AGENTS.md")
	if err := os.WriteFile(link, []byte("stale"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := prepareLane(askLane()); err != nil {
		t.Fatal(err)
	}
	got, err := os.Readlink(link)
	if err != nil || got != target {
		t.Fatalf("AGENTS.md link = %q, %v; want %q", got, err, target)
	}
	st, err := os.Stat(askDir)
	if err != nil {
		t.Fatal(err)
	}
	if st.Mode().Perm() != 0o700 {
		t.Fatalf("ask dir mode = %v, want 0700", st.Mode().Perm())
	}
}

func TestPreparePublicLaneKeepsExistingMode(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "vault")
	if err := os.MkdirAll(dir, 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o750); err != nil {
		t.Fatal(err)
	}
	if err := prepareLane(lane{Name: laneRyoku, Cwd: dir}); err != nil {
		t.Fatal(err)
	}
	st, err := os.Stat(dir)
	if err != nil {
		t.Fatal(err)
	}
	if st.Mode().Perm() != 0o750 {
		t.Fatalf("public lane mode = %v, want existing 0750", st.Mode().Perm())
	}
}

// A lane's history drawer lists the sessions opened in its cwd; a session
// the agent cannot place (no cwd) shows in every lane rather than nowhere,
// and a cwd reached through a symlink is the same directory.
func TestLaneOwnsSession(t *testing.T) {
	real := t.TempDir()
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(real, link); err != nil {
		t.Skip("symlinks unavailable:", err)
	}
	if !(lane{Cwd: link}).ownsSession(SessionMeta{Cwd: real}) || !(lane{Cwd: real}).ownsSession(SessionMeta{Cwd: link}) {
		t.Fatal("a symlinked spelling of the lane dir must own the same sessions")
	}
	l := lane{Name: "x", Cwd: "/home/u/.local/share/ryoku/rashin"}
	cases := []struct {
		cwd  string
		want bool
	}{
		{"/home/u/.local/share/ryoku/rashin", true},
		{"/home/u/.local/share/ryoku/rashin/", true},
		{"/home/u/.local/state/ryoku/rashin-chat", false},
		{"/home/u/Work/foo", false},
		{"", true},
	}
	for _, c := range cases {
		if got := l.ownsSession(SessionMeta{Cwd: c.cwd}); got != c.want {
			t.Errorf("ownsSession(%q) = %v, want %v", c.cwd, got, c.want)
		}
	}
}
