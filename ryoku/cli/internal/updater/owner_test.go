package updater

import (
	"path/filepath"
	"strings"
	"testing"

	wm "ryoku-wm"
)

// ownerFixture stands up a temp XDG_CONFIG_HOME, XDG_STATE_HOME and
// RYOKU_CONFIG_BASE with a small Ryoku tree, an overlay fork, a store, and a
// user file, so classify() can be exercised against every branch. Paths that a
// compositor owns are asked of the seam rather than hardcoded, so the fixture
// tracks the real provider layout.
type ownerFixture struct {
	cfg      string
	editsDir string

	provShipped   string // a shipped Ryoku file under the provider's tree
	provUserFile  string // the provider's hand-edit include (also a seed)
	provSeed      string // a per-machine seed under the provider's tree
	provGenerated string // a provider-authored (generated) file
}

func setupOwner(t *testing.T) ownerFixture {
	t.Helper()
	home := t.TempDir()
	cfg := filepath.Join(home, ".config")
	base := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", cfg)
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("RYOKU_CONFIG_BASE", base)

	p := wm.Providers()[0]
	dir := wm.ConfigDir(p)
	f := ownerFixture{
		cfg:          cfg,
		editsDir:     filepath.Join(cfg, "ryoku", "user_edits"),
		provShipped:  dir + "/extra.conf",
		provUserFile: wm.ConfigFiles(p)[0],
		provSeed:     wm.ConfigSeeds(p)[0],
	}
	for _, g := range wm.GeneratedConfig(p) {
		if !strings.HasPrefix(g, "ryoku/user_edits/") { // skip the overlay copies
			f.provGenerated = g
			break
		}
	}

	// The shipped baseline: a provider file, its seed and hand-edit include, the
	// terminal config (a tree with a user-override file), the shell tree, and a
	// plain tree with no override.
	writeFile(t, filepath.Join(base, f.provShipped), "shipped\n")
	writeFile(t, filepath.Join(base, f.provUserFile), "seed\n")
	writeFile(t, filepath.Join(base, f.provSeed), "seed\n")
	writeFile(t, filepath.Join(base, "kitty/kitty.conf"), "shipped\n")
	writeFile(t, filepath.Join(base, "kitty/theme.conf"), "shipped\n")
	writeFile(t, filepath.Join(base, "quickshell/shell/shell.qml"), "// shell\n")
	writeFile(t, filepath.Join(base, "foo/bar.conf"), "shipped\n")

	// Live tree: a store, a fork of kitty.conf (so it reads as forked), and a
	// plain user file the package never ships.
	writeFile(t, filepath.Join(cfg, "ryoku/shell.json"), "{}\n")
	writeFile(t, filepath.Join(f.editsDir, "kitty/kitty.conf"), "mine\n")
	writeFile(t, filepath.Join(cfg, "randomapp/conf.ini"), "mine\n")
	return f
}

func TestOwnerClassify(t *testing.T) {
	f := setupOwner(t)
	e := newOwnerEnv()

	abs := func(rel string) string { return filepath.Join(f.cfg, filepath.FromSlash(rel)) }
	fork := func(rel string) string { return filepath.Join(f.editsDir, filepath.FromSlash(rel)) }

	cases := []struct {
		name      string
		arg       string
		wantClass string
		wantEdit  string // "" means expect an empty edit; "\x00" means don't check
	}{
		// overlay wins even though the same rel is a shipped, forked file.
		{"overlay", abs("ryoku/user_edits/kitty/kitty.conf"), "overlay", abs("ryoku/user_edits/kitty/kitty.conf")},
		{"overlay dir itself", f.editsDir, "overlay", f.editsDir},

		// forked beats ryoku: a shipped file the user copied into the overlay.
		{"forked shipped file", abs("kitty/kitty.conf"), "forked", fork("kitty/kitty.conf")},

		// generated: authored by the provider, changed through the Hub.
		{"generated", abs(f.provGenerated), "generated", ""},

		// store: a Ryoku tool's JSON under ~/.config/ryoku.
		{"store", abs("ryoku/shell.json"), "store", ""},

		// seed beats both ryoku and user-override: a shipped file seeded once.
		{"seed hand-edit include", abs(f.provUserFile), "seed", abs(f.provUserFile)},
		{"seed per-machine", abs(f.provSeed), "seed", abs(f.provSeed)},

		// user-override: a dedicated user file, never shipped.
		{"user-override", abs("kitty/user.conf"), "user-override", abs("kitty/user.conf")},

		// ryoku, with the edit pointed at the right place per tree.
		{"ryoku quickshell empty edit", abs("quickshell/shell/shell.qml"), "ryoku", ""},
		{"ryoku kitty -> user.conf", abs("kitty/theme.conf"), "ryoku", abs("kitty/user.conf")},
		{"ryoku provider -> user include", abs(f.provShipped), "ryoku", abs(f.provUserFile)},
		{"ryoku plain tree -> overlay fork", abs("foo/bar.conf"), "ryoku", fork("foo/bar.conf")},

		// user: under ~/.config, never shipped.
		{"user", abs("randomapp/conf.ini"), "user", abs("randomapp/conf.ini")},

		// path resolution: ~/... and a bare relative both land under ~/.config.
		{"tilde path", "~/.config/kitty/user.conf", "user-override", abs("kitty/user.conf")},
		{"relative path", "kitty/user.conf", "user-override", abs("kitty/user.conf")},

		// outside ~/.config and owned by no package: unmanaged.
		{"unmanaged outside", filepath.Join(t.TempDir(), "nope.conf"), "unmanaged", "\x00"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := e.classify(c.arg)
			if got.Class != c.wantClass {
				t.Fatalf("class = %q, want %q", got.Class, c.wantClass)
			}
			if c.wantEdit != "\x00" && got.Edit != c.wantEdit {
				t.Fatalf("edit = %q, want %q", got.Edit, c.wantEdit)
			}
		})
	}
}

// A plain shipped tree with no override file forks through the overlay, while a
// shipped file that gains a fork flips from ryoku to forked: the two states of
// the same path prove forked wins over ryoku.
func TestOwnerForkFlipsClass(t *testing.T) {
	f := setupOwner(t)
	e := newOwnerEnv()

	// theme.conf is shipped with no fork -> ryoku.
	if got := e.classify(filepath.Join(f.cfg, "kitty/theme.conf")); got.Class != "ryoku" {
		t.Fatalf("unforked shipped file class = %q, want ryoku", got.Class)
	}
	// dropping a fork of it makes the same path read as forked.
	writeFile(t, filepath.Join(f.editsDir, "kitty/theme.conf"), "mine\n")
	e = newOwnerEnv()
	got := e.classify(filepath.Join(f.cfg, "kitty/theme.conf"))
	if got.Class != "forked" {
		t.Fatalf("forked shipped file class = %q, want forked", got.Class)
	}
	if want := filepath.Join(f.editsDir, "kitty/theme.conf"); got.Edit != want {
		t.Fatalf("forked edit = %q, want %q", got.Edit, want)
	}
}

// With no shipped baseline on disk (a dev box) the quickshell tree is still
// Ryoku-owned, because materialize converges it wholesale, while an ordinary
// unshipped path degrades to a plain user file.
func TestOwnerNoBaseline(t *testing.T) {
	f := setupOwner(t)
	t.Setenv("RYOKU_CONFIG_BASE", filepath.Join(t.TempDir(), "absent"))
	e := newOwnerEnv()

	if got := e.classify(filepath.Join(f.cfg, "quickshell/shell/shell.qml")); got.Class != "ryoku" {
		t.Fatalf("quickshell class without baseline = %q, want ryoku", got.Class)
	}
	if got := e.classify(filepath.Join(f.cfg, "kitty/theme.conf")); got.Class != "user" {
		t.Fatalf("unshipped file without baseline = %q, want user", got.Class)
	}
}
