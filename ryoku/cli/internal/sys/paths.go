package sys

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// Home is the user's home directory.
func Home() string {
	if h, err := os.UserHomeDir(); err == nil {
		return h
	}
	return os.Getenv("HOME")
}

// Xdg returns envVar's value, or Home()/fallback when it is unset.
func Xdg(envVar, fallback string) string {
	if v := os.Getenv(envVar); v != "" {
		return v
	}
	return filepath.Join(Home(), fallback)
}

// ConfigHome is $XDG_CONFIG_HOME (default ~/.config).
func ConfigHome() string { return Xdg("XDG_CONFIG_HOME", ".config") }

// DataDirs returns XDG data roots in lookup order, including active NixOS
// profiles when the session does not provide XDG_DATA_DIRS.
func DataDirs() []string {
	raw := strings.TrimSpace(os.Getenv("XDG_DATA_DIRS"))
	if raw == "" {
		if NixBackend() {
			raw = strings.Join([]string{
				filepath.Join(Home(), ".local", "share"),
				filepath.Join(Home(), ".nix-profile", "share"),
				filepath.Join("/etc/profiles/per-user", os.Getenv("USER"), "share"),
				"/run/current-system/sw/share",
				"/usr/local/share",
				"/usr/share",
			}, ":")
		} else {
			raw = "/usr/local/share:/usr/share"
		}
	}

	var out []string
	seen := map[string]bool{}
	for _, dir := range strings.Split(raw, ":") {
		dir = strings.TrimSpace(dir)
		if dir == "" || seen[dir] {
			continue
		}
		seen[dir] = true
		out = append(out, dir)
	}
	return out
}

// PicturesDir is the user's Pictures folder: $XDG_PICTURES_DIR when the session
// exports it, else the XDG_PICTURES_DIR line of user-dirs.dirs (a terminal or a
// service that did not inherit the login environment), else ~/Pictures. A
// localized desktop keeps its pictures in ~/Imágenes, ~/Bilder and so on, and a
// hardcoded ~/Pictures grows a second, empty folder beside the real one.
func PicturesDir() string {
	if d := normalizePicturesDir(os.Getenv("XDG_PICTURES_DIR")); d != "" {
		return d
	}
	if d := userDirsPictures(filepath.Join(ConfigHome(), "user-dirs.dirs")); d != "" {
		return d
	}
	return filepath.Join(Home(), "Pictures")
}

func normalizePicturesDir(value string) string {
	v := strings.TrimSpace(value)
	v = strings.Trim(v, `"'`)
	switch {
	case v == "$HOME":
		v = Home()
	case strings.HasPrefix(v, "$HOME/"):
		v = filepath.Join(Home(), strings.TrimPrefix(v, "$HOME/"))
	}
	if !filepath.IsAbs(v) {
		return ""
	}
	v = filepath.Clean(v)
	if v == filepath.Clean(Home()) {
		return ""
	}
	return v
}

// userDirsPictures reads XDG_PICTURES_DIR from a user-dirs.dirs file, expanding
// the $HOME the format allows. Anything that is not an absolute path after the
// expansion is rejected, and "" says the file has no usable answer.
func userDirsPictures(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	const key = "XDG_PICTURES_DIR="
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if !strings.HasPrefix(line, key) {
			continue
		}
		if v := normalizePicturesDir(strings.TrimPrefix(line, key)); v != "" {
			return v
		}
	}
	return ""
}

// StateDir is the CLI's state root, $XDG_STATE_HOME/ryoku (default
// ~/.local/state/ryoku).
func StateDir() string {
	return filepath.Join(Xdg("XDG_STATE_HOME", ".local/state"), "ryoku")
}

// IsBtrfs reports whether path lives on a btrfs filesystem.
func IsBtrfs(path string) bool {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return false
	}
	return int64(st.Type) == 0x9123683E // BTRFS_SUPER_MAGIC
}

// FreeBytes is the space available to a non-root writer under path, and whether
// the filesystem could be read at all.
func FreeBytes(path string) (uint64, bool) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return 0, false
	}
	return st.Bavail * uint64(st.Bsize), true
}

// IsBtrfsSubvolumeRoot reports whether path is the root of a btrfs subvolume:
// those always carry inode 256.
func IsBtrfsSubvolumeRoot(path string) bool {
	var st syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return false
	}
	return st.Ino == 256
}
