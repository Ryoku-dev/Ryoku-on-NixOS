package main

import (
	"os"
	"path/filepath"
	"testing"
)

// skillEnv sets a hermetic HOME plus a temp skill source (RYOKU_RASHIN_SKILLS),
// and neutralises the dev-checkout resolution so only the override resolves. It
// returns the home dir and the resolved `ryoku` skill dir.
func skillEnv(t *testing.T) (string, string) {
	t.Helper()
	h := t.TempDir()
	t.Setenv("HOME", h)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(h, ".config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(h, ".local", "share"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(h, ".local", "state"))
	t.Setenv("RYOKU_RASHIN_VAULT", filepath.Join(h, "vault"))
	t.Setenv("RYOKU_RASHIN_REPO", "") // no dev checkout in resolution
	skills := t.TempDir()
	ryoku := filepath.Join(skills, "ryoku")
	if err := os.MkdirAll(ryoku, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(ryoku, "SKILL.md"), []byte("# ryoku\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_RASHIN_SKILLS", skills)
	return h, ryoku
}

func assertSkillLink(t *testing.T, link, want string) {
	t.Helper()
	fi, err := os.Lstat(link)
	if err != nil {
		t.Fatalf("expected skill link %s: %v", link, err)
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("%s is not a symlink", link)
	}
	dest, _ := os.Readlink(link)
	if dest != want {
		t.Fatalf("%s -> %q, want %q", link, dest, want)
	}
}

func TestWireSkillLinksApplicableLocations(t *testing.T) {
	h, ryoku := skillEnv(t)
	// claude and codex present; omp absent (its link must be skipped).
	if err := os.MkdirAll(filepath.Join(h, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(h, ".codex"), 0o755); err != nil {
		t.Fatal(err)
	}
	n, err := WireSkill()
	if err != nil {
		t.Fatalf("WireSkill: %v", err)
	}
	if n < 4 {
		t.Fatalf("WireSkill wrote %d links; want at least 4", n)
	}
	// Always-created homes and the two present agents are linked.
	assertSkillLink(t, filepath.Join(h, ".agents", "skills", "ryoku"), ryoku)
	assertSkillLink(t, filepath.Join(h, ".hermes", "skills", "ryoku"), ryoku)
	assertSkillLink(t, filepath.Join(h, ".claude", "skills", "ryoku"), ryoku)
	assertSkillLink(t, filepath.Join(h, ".codex", "skills", "ryoku"), ryoku)
	// omp absent, so no omp link was created.
	if _, err := os.Lstat(filepath.Join(h, ".omp", "agent", "skills", "ryoku")); !os.IsNotExist(err) {
		t.Fatal("omp skill link created without ~/.omp")
	}
	// Idempotent: a second wire changes nothing on disk.
	if _, err := WireSkill(); err != nil {
		t.Fatalf("second WireSkill: %v", err)
	}
	assertSkillLink(t, filepath.Join(h, ".hermes", "skills", "ryoku"), ryoku)
}

func TestWireSkillNoOpWhenSkillDirMissing(t *testing.T) {
	h := t.TempDir()
	t.Setenv("HOME", h)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(h, ".config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(h, ".local", "state"))
	t.Setenv("RYOKU_RASHIN_REPO", "")
	// Override points at a dir with no SKILL.md, so nothing resolves.
	t.Setenv("RYOKU_RASHIN_SKILLS", t.TempDir())
	n, err := WireSkill()
	if err != nil || n != 0 {
		t.Fatalf("WireSkill on a box with no skill dir: n=%d err=%v", n, err)
	}
	if _, err := os.Lstat(filepath.Join(h, ".hermes", "skills", "ryoku")); !os.IsNotExist(err) {
		t.Fatal("WireSkill created a link with no skill source")
	}
}

func TestSymlinkForceKeepsForeignSkillDir(t *testing.T) {
	dir := t.TempDir()
	link := filepath.Join(dir, "ryoku")
	if err := os.MkdirAll(link, 0o755); err != nil { // a real skill dir sits here
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(link, "SKILL.md"), []byte("---\nname: someone-else\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	wrote, err := symlinkForce(link, t.TempDir())
	if err != nil {
		t.Fatalf("symlinkForce: %v", err)
	}
	if wrote {
		t.Fatal("symlinkForce reported writing over a foreign skill dir")
	}
	fi, _ := os.Lstat(link)
	if fi.Mode()&os.ModeSymlink != 0 {
		t.Fatal("symlinkForce clobbered a foreign skill dir")
	}
}

func TestSymlinkForceKeepsForeignSkillSymlink(t *testing.T) {
	_, ours := skillEnv(t)
	dir := t.TempDir()
	foreign := filepath.Join(dir, "foreign")
	if err := os.MkdirAll(foreign, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(foreign, "SKILL.md"), []byte("---\nname: someone-else\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "ryoku")
	if err := os.Symlink(foreign, link); err != nil {
		t.Fatal(err)
	}
	wrote, err := symlinkForce(link, ours)
	if err != nil {
		t.Fatalf("symlinkForce: %v", err)
	}
	if wrote {
		t.Fatal("symlinkForce reported replacing a foreign link")
	}
	if dest, err := os.Readlink(link); err != nil || dest != foreign {
		t.Fatalf("foreign link = %q, %v", dest, err)
	}
}

// Hermes keeps skills in category folders: ~/.hermes/skills/ryoku is a real
// directory (no SKILL.md of its own) and the skill lives inside it as a
// nested ryoku link. Wire must lay the link inside, status must read the
// skill as wired, and unwire must remove the link and leave the folder.
func TestSkillLinkInsideCategoryFolder(t *testing.T) {
	h, ryoku := skillEnv(t)
	cat := filepath.Join(h, ".hermes", "skills", "ryoku")
	if err := os.MkdirAll(cat, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := WireSkill(); err != nil {
		t.Fatalf("WireSkill: %v", err)
	}
	assertSkillLink(t, filepath.Join(cat, "ryoku"), ryoku)
	if !isOurSkillLink(cat) {
		t.Fatal("a category folder holding our nested link must read as wired")
	}
	UnwireSkill()
	if _, err := os.Lstat(filepath.Join(cat, "ryoku")); !os.IsNotExist(err) {
		t.Fatal("UnwireSkill left the nested link")
	}
	if fi, err := os.Lstat(cat); err != nil || !fi.IsDir() {
		t.Fatal("UnwireSkill removed the user's category folder")
	}
}

func TestUnwireSkillRemovesOnlyOurs(t *testing.T) {
	h, ryoku := skillEnv(t)
	if _, err := WireSkill(); err != nil {
		t.Fatal(err)
	}
	// A foreign symlink at a skills/ryoku path must be left alone.
	foreign := filepath.Join(h, ".hermes", "profiles", "p1", "skills")
	if err := os.MkdirAll(foreign, 0o755); err != nil {
		t.Fatal(err)
	}
	other := t.TempDir()
	if err := os.Symlink(other, filepath.Join(foreign, "ryoku")); err != nil {
		t.Fatal(err)
	}
	UnwireSkill()
	// Ours is gone.
	if _, err := os.Lstat(filepath.Join(h, ".hermes", "skills", "ryoku")); !os.IsNotExist(err) {
		t.Fatal("UnwireSkill left our hermes link")
	}
	if _, err := os.Lstat(filepath.Join(h, ".agents", "skills", "ryoku")); !os.IsNotExist(err) {
		t.Fatal("UnwireSkill left our agents link")
	}
	// The foreign link survives.
	if _, err := os.Lstat(filepath.Join(foreign, "ryoku")); err != nil {
		t.Fatal("UnwireSkill removed a foreign symlink")
	}
	_ = ryoku
}

func TestDetectAgentsReportsSkillWired(t *testing.T) {
	h, _ := skillEnv(t)
	if err := os.MkdirAll(filepath.Join(h, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := Wire("claude"); err != nil {
		t.Fatal(err)
	}
	var claude, opencode Agent
	for _, a := range DetectAgents() {
		switch a.ID {
		case "claude":
			claude = a
		case "opencode":
			opencode = a
		}
	}
	if !claude.SkillWired {
		t.Fatal("claude should report skillWired after Wire")
	}
	if opencode.SkillWired {
		t.Fatal("opencode has no skills dir and must report skillWired=false")
	}
}

// A link laid by another checkout's deploy still points at a directory carrying
// our SKILL.md (frontmatter name: ryoku), so it counts as wired and unwire may
// remove it; a foreign skill dir without the marker stays foreign.
func TestSkillLinkRecognisedByMarker(t *testing.T) {
	h, _ := skillEnv(t)
	other := filepath.Join(t.TempDir(), "elsewhere", "ryoku")
	if err := os.MkdirAll(other, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(other, "SKILL.md"), []byte("---\nname: ryoku\ndescription: x\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(h, ".hermes", "skills", "ryoku")
	if err := os.MkdirAll(filepath.Dir(link), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(other, link); err != nil {
		t.Fatal(err)
	}
	if !isOurSkillLink(link) {
		t.Fatal("a link to a dir with our SKILL.md marker must count as ours")
	}
	foreign := filepath.Join(t.TempDir(), "ryoku")
	if err := os.MkdirAll(foreign, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(foreign, "SKILL.md"), []byte("---\nname: someone-else\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(link); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(foreign, link); err != nil {
		t.Fatal(err)
	}
	if isOurSkillLink(link) {
		t.Fatal("a foreign skill without the marker must not count as ours")
	}
}
