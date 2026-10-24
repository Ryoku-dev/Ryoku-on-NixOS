package sys

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPicturesDir(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_PICTURES_DIR", "")

	if got, want := PicturesDir(), filepath.Join(home, "Pictures"); got != want {
		t.Errorf("no env, no file: got %q, want %q", got, want)
	}

	write := func(body string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Join(home, ".config"), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(home, ".config", "user-dirs.dirs"), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	write("# written by xdg-user-dirs-update\nXDG_DOWNLOAD_DIR=\"$HOME/Descargas\"\nXDG_PICTURES_DIR=\"$HOME/My Pictures\"\n")
	if got, want := PicturesDir(), filepath.Join(home, "My Pictures"); got != want {
		t.Errorf("quoted user-dirs.dirs: got %q, want %q", got, want)
	}

	write("XDG_PICTURES_DIR=$HOME/Imágenes\n")
	if got, want := PicturesDir(), filepath.Join(home, "Imágenes"); got != want {
		t.Errorf("unquoted user-dirs.dirs: got %q, want %q", got, want)
	}

	// xdg-user-dirs writes $HOME itself for a folder the user disabled; that is
	// not a Pictures folder, so the default wins.
	write("XDG_PICTURES_DIR=\"$HOME/\"\n")
	if got, want := PicturesDir(), filepath.Join(home, "Pictures"); got != want {
		t.Errorf("disabled file folder: got %q, want %q", got, want)
	}

	write("XDG_PICTURES_DIR=\"$HOME2/not-pictures\"\n")
	if got, want := PicturesDir(), filepath.Join(home, "Pictures"); got != want {
		t.Errorf("non-HOME variable: got %q, want %q", got, want)
	}

	t.Setenv("XDG_PICTURES_DIR", home)
	if got, want := PicturesDir(), filepath.Join(home, "Pictures"); got != want {
		t.Errorf("disabled env folder: got %q, want %q", got, want)
	}
	t.Setenv("XDG_PICTURES_DIR", "$HOME/Photos")
	if got, want := PicturesDir(), filepath.Join(home, "Photos"); got != want {
		t.Errorf("expanded env folder: got %q, want %q", got, want)
	}
	t.Setenv("XDG_PICTURES_DIR", "/data/pics")
	if got := PicturesDir(); got != "/data/pics" {
		t.Errorf("session env wins: got %q", got)
	}
}
