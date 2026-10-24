package doctor

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

var homePrefixPattern = regexp.MustCompile(`/home/[A-Za-z0-9._-]+`)

func reconcileRyogamiHome(checkOnly bool) recResult {
	changed, err := repairRyogamiHomePaths(sys.Home(), checkOnly)
	if err != nil {
		return failRes(i18n.T("could not repair Ryogami paths after the account rename: %v"), err)
	}
	if len(changed) == 0 {
		return okRes(i18n.T("Ryogami state follows the current user home"))
	}
	if checkOnly {
		return wouldRes(i18n.T("Ryogami still references the previous user home in %d state file(s)"), len(changed)).
			withFix(i18n.T("ryoku doctor rewrites those paths to %s"), sys.Home())
	}

	// A running daemon has already read ryogami.json and its cache root. Restart it
	// after the files are repaired so Super+W sees the moved catalogue immediately.
	_ = ryogamiService([]string{"--user", "daemon-reload"})
	_ = ryogamiService([]string{"--user", "try-restart", ryogamiUserUnit})
	return fixedRes(i18n.T("rewrote Ryogami state for the current user home in %d file(s)"), len(changed))
}

func repairRyogamiHomePaths(home string, checkOnly bool) ([]string, error) {
	paths, err := ryogamiHomePathCandidates()
	if err != nil {
		return nil, err
	}
	var changed []string
	for _, path := range paths {
		info, err := os.Lstat(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return changed, err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			target, err := os.Readlink(path)
			if err != nil {
				return changed, err
			}
			next := rewriteStaleHome([]byte(target), home)
			if bytes.Equal(next, []byte(target)) {
				continue
			}
			changed = append(changed, path)
			if !checkOnly {
				if err := replaceSymlink(path, string(next)); err != nil {
					return changed, err
				}
			}
			continue
		}
		if !info.Mode().IsRegular() {
			continue
		}
		raw, err := os.ReadFile(path)
		if err != nil {
			return changed, err
		}
		next := rewriteStaleHome(raw, home)
		if bytes.Equal(raw, next) {
			continue
		}
		changed = append(changed, path)
		if !checkOnly {
			if err := replaceFile(path, next, info.Mode().Perm()); err != nil {
				return changed, err
			}
		}
	}
	return changed, nil
}

func rewriteStaleHome(raw []byte, home string) []byte {
	current := filepath.Clean(home)
	roots := homePrefixPattern.FindAll(raw, -1)
	for _, rootBytes := range roots {
		root := string(rootBytes)
		if filepath.Clean(root) == current {
			continue
		}
		if _, err := os.Stat(root); err == nil || !os.IsNotExist(err) {
			continue
		}
		raw = bytes.ReplaceAll(raw, rootBytes, []byte(current))
	}
	return raw
}

func ryogamiHomePathCandidates() ([]string, error) {
	config := sys.ConfigHome()
	state := sys.Xdg("XDG_STATE_HOME", ".local/state")
	cache := sys.Xdg("XDG_CACHE_HOME", ".cache")
	data := sys.Xdg("XDG_DATA_HOME", ".local/share")
	cacheRoots := []string{filepath.Join(cache, "ryogami")}
	configPath := filepath.Join(config, "ryoku", "ryogami.json")
	if raw, err := os.ReadFile(configPath); err == nil {
		var cfg struct {
			Paths struct {
				Cache string `json:"cache"`
			} `json:"paths"`
		}
		if json.Unmarshal(rewriteStaleHome(raw, sys.Home()), &cfg) == nil && cfg.Paths.Cache != "" {
			custom := cfg.Paths.Cache
			if custom == "~" {
				custom = sys.Home()
			} else if strings.HasPrefix(custom, "~/") {
				custom = filepath.Join(sys.Home(), custom[2:])
			}
			cacheRoots = append(cacheRoots, custom)
		}
	}
	seen := map[string]bool{}
	var paths []string
	add := func(path string) {
		if !seen[path] {
			seen[path] = true
			paths = append(paths, path)
		}
	}
	for _, path := range []string{
		filepath.Join(config, "ryoku", "ryogami.json"),
		filepath.Join(config, "ryoku", "shell.json"),
		filepath.Join(config, "systemd", "user", "ryogami.service.d", "ryoku-dev-bin.conf"),
		filepath.Join(config, "service-env", "RYOGAMI_SHELL_QML"),
		filepath.Join(state, "ryoku-wallpaper"),
		filepath.Join(state, "ryoku-wallpaper.json"),
		filepath.Join(state, "quickshell", "states.json"),
	} {
		add(path)
	}
	workshopDirs := []string{
		filepath.Join(sys.Home(), ".local", "share", "Steam", "steamapps", "workshop", "content", "431960"),
		filepath.Join(sys.Home(), ".steam", "steam", "steamapps", "workshop", "content", "431960"),
		filepath.Join(sys.Home(), ".var", "app", "com.valvesoftware.Steam", "data", "Steam", "steamapps", "workshop", "content", "431960"),
	}
	for _, root := range cacheRoots {
		raw, err := os.ReadFile(filepath.Join(root, "wallpaper", "state.json"))
		if err != nil {
			continue
		}
		var settings map[string]string
		if json.Unmarshal(rewriteStaleHome(raw, sys.Home()), &settings) != nil {
			continue
		}
		if workshop := settings["paths.steamWorkshop"]; workshop != "" {
			if workshop == "~" {
				workshop = sys.Home()
			} else if strings.HasPrefix(workshop, "~/") {
				workshop = filepath.Join(sys.Home(), workshop[2:])
			}
			workshopDirs = append(workshopDirs, workshop)
		}
	}
	for _, dir := range workshopDirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if entry.Type()&os.ModeSymlink != 0 {
				add(filepath.Join(dir, entry.Name()))
			}
		}
	}
	roots := []string{
		filepath.Join(config, "ryogami-wall"),
		filepath.Join(data, "ryogami"),
	}
	roots = append(roots, cacheRoots...)
	for _, root := range roots {
		err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
			if os.IsNotExist(err) {
				return nil
			}
			if err != nil {
				return err
			}
			if entry.Type()&os.ModeSymlink != 0 || (!entry.IsDir() && strings.EqualFold(filepath.Ext(path), ".json")) {
				add(path)
			}
			return nil
		})
		if err != nil && !os.IsNotExist(err) {
			return nil, fmt.Errorf("scan %s: %w", root, err)
		}
	}
	sort.Strings(paths)
	return paths, nil
}

func replaceFile(path string, body []byte, mode fs.FileMode) error {
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, body, mode); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func replaceSymlink(path, target string) error {
	tmp := path + ".ryoku-tmp"
	_ = os.Remove(tmp)
	if err := os.Symlink(target, tmp); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}
