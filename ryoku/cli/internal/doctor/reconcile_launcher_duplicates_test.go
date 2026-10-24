package doctor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const upstreamNvim = `[Desktop Entry]
Name=Neovim
TryExec=nvim
Exec=nvim %F
Terminal=true
NoDisplay=false
MimeType=text/plain;
Actions=new;

[Desktop Action new]
Name=New file
Exec=nvim
NoDisplay=false
`

func launcherBox(t *testing.T, withRyoku bool) (user, system string) {
	t.Helper()
	root := t.TempDir()
	t.Setenv("HOME", root)
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(root, "state"))
	sysShare := filepath.Join(root, "usr", "share")
	t.Setenv("XDG_DATA_DIRS", sysShare)
	user = filepath.Join(root, "data", "applications")
	system = filepath.Join(sysShare, "applications")
	if err := os.MkdirAll(system, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(system, "nvim.desktop"), []byte(upstreamNvim), 0o644); err != nil {
		t.Fatal(err)
	}
	if withRyoku {
		if err := os.WriteFile(filepath.Join(system, "ryoku-nvim.desktop"), []byte("[Desktop Entry]\nName=Neovim\nExec=kitty -e nvim %F\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return user, system
}

func TestLauncherDuplicatesHidesThePackageEntryOnce(t *testing.T) {
	user, _ := launcherBox(t, true)

	if r := reconcileLauncherDuplicates(true); r.status != recWouldFix {
		t.Fatalf("check: status=%s want would-fix (detail=%s)", r.status.label(), r.detail)
	}
	if _, err := os.Stat(filepath.Join(user, "nvim.desktop")); !os.IsNotExist(err) {
		t.Fatal("check-only run wrote the override")
	}

	if r := reconcileLauncherDuplicates(false); r.status != recFixed {
		t.Fatalf("fix: status=%s want fixed (detail=%s)", r.status.label(), r.detail)
	}
	b, err := os.ReadFile(filepath.Join(user, "nvim.desktop"))
	if err != nil {
		t.Fatal(err)
	}
	got := string(b)
	entry, action, _ := strings.Cut(got, "[Desktop Action new]")
	if strings.Count(entry, "NoDisplay=") != 1 || !strings.Contains(entry, "NoDisplay=true") {
		t.Fatalf("[Desktop Entry] must carry exactly NoDisplay=true:\n%s", got)
	}
	if !strings.Contains(entry, "MimeType=text/plain;") || !strings.Contains(entry, "Exec=nvim %F") {
		t.Fatalf("override lost the package's keys:\n%s", got)
	}
	if !strings.Contains(action, "NoDisplay=false") {
		t.Fatalf("an action group was rewritten:\n%s", got)
	}

	if r := reconcileLauncherDuplicates(false); r.status != recOK {
		t.Fatalf("second run: status=%s want ok (detail=%s)", r.status.label(), r.detail)
	}

	// A user who deletes the override keeps the package's entry.
	if err := os.Remove(filepath.Join(user, "nvim.desktop")); err != nil {
		t.Fatal(err)
	}
	if r := reconcileLauncherDuplicates(false); r.status != recOK {
		t.Fatalf("after removal: status=%s want ok (detail=%s)", r.status.label(), r.detail)
	}
	if _, err := os.Stat(filepath.Join(user, "nvim.desktop")); !os.IsNotExist(err) {
		t.Fatal("a removed override came back")
	}
}

func TestLauncherDuplicatesLeavesOtherBoxesAlone(t *testing.T) {
	user, _ := launcherBox(t, false)
	if r := reconcileLauncherDuplicates(false); r.status != recOK {
		t.Fatalf("no Ryoku entry: status=%s want ok (detail=%s)", r.status.label(), r.detail)
	}
	if _, err := os.Stat(filepath.Join(user, "nvim.desktop")); !os.IsNotExist(err) {
		t.Fatal("hid nvim.desktop without a Ryoku replacement")
	}

	user, _ = launcherBox(t, true)
	own := "[Desktop Entry]\nName=My Neovim\nExec=nvim\n"
	if err := os.MkdirAll(user, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(user, "nvim.desktop"), []byte(own), 0o644); err != nil {
		t.Fatal(err)
	}
	if r := reconcileLauncherDuplicates(false); r.status != recOK {
		t.Fatalf("user entry: status=%s want ok (detail=%s)", r.status.label(), r.detail)
	}
	if b, _ := os.ReadFile(filepath.Join(user, "nvim.desktop")); string(b) != own {
		t.Fatalf("the user's own nvim.desktop was rewritten:\n%s", b)
	}
}
