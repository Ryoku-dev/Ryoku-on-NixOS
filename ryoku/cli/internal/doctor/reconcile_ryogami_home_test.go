package doctor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ryoku-cli/internal/host"
)

func TestReconcileRyogamiHomeAfterUsernameChange(t *testing.T) {
	root := t.TempDir()
	home := filepath.Join(root, "new-user")
	config := filepath.Join(home, ".config")
	cache := filepath.Join(home, ".cache")
	state := filepath.Join(home, ".local", "state")
	data := filepath.Join(home, ".local", "share")
	customCache := filepath.Join(home, "custom-ryogami")
	for key, value := range map[string]string{
		"HOME": home, "XDG_CONFIG_HOME": config, "XDG_CACHE_HOME": cache,
		"XDG_STATE_HOME": state, "XDG_DATA_HOME": data,
	} {
		t.Setenv(key, value)
	}

	const oldHome = "/home/ryoku-renamed-user-fixture"
	files := map[string]string{
		filepath.Join(config, "ryoku", "ryogami.json"):                                      `{"paths":{"wallpaper":"` + oldHome + `/Pictures/Wallpapers","cache":"` + oldHome + `/custom-ryogami"}}`,
		filepath.Join(config, "ryoku", "shell.json"):                                        `{"wallpaper":{"custom":"` + oldHome + `/Pictures/hero.png"}}`,
		filepath.Join(config, "systemd", "user", "ryogami.service.d", "ryoku-dev-bin.conf"): "[Service]\nExecStart=" + oldHome + "/.local/bin/ryogami\nEnvironment=RYOGAMI_SHELL_QML=" + oldHome + "/.local/share/ryogami/shell.qml\n",
		filepath.Join(config, "service-env", "RYOGAMI_SHELL_QML"):                           oldHome + "/.local/share/ryogami/shell.qml",
		filepath.Join(customCache, "outputs.json"):                                          `{"*":{"type":"static","path":"` + oldHome + `/Pictures/Wallpapers/scene.png"}}`,
		filepath.Join(customCache, "wallpaper", "index.json"):                               `{"scene.png":{"key":"scene.png","path":"` + oldHome + `/Pictures/Wallpapers/scene.png","thumb":"` + oldHome + `/custom-ryogami/wallpaper/thumbs/scene.webp"}}`,
		filepath.Join(customCache, "wallpaper", "state.json"):                               `{"semantic.manifest":"` + oldHome + `/.local/share/ryogami/models/semantic-pack.json","paths.steamWorkshop":"` + oldHome + `/SteamWorkshop"}`,
		filepath.Join(data, "ryogami", "trash", "manifest.json"):                            `[{"original_path":"` + oldHome + `/Pictures/Wallpapers/original.png","stored_path":"` + oldHome + `/.local/share/ryogami/trash/original.png"}]`,
		filepath.Join(state, "ryoku-wallpaper"):                                             oldHome + "/Pictures/Wallpapers/scene.png\n",
		filepath.Join(state, "ryoku-wallpaper.json"):                                        `{"default":"` + oldHome + `/Pictures/Wallpapers/scene.png"}`,
		filepath.Join(state, "quickshell", "states.json"):                                   `{"background":{"recentWallpapers":["` + oldHome + `/Pictures/Wallpapers/scene.png"]}}`,
	}
	for path, body := range files {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	newTarget := filepath.Join(home, "Pictures", "Wallpapers", "scene.png")
	if err := os.MkdirAll(filepath.Dir(newTarget), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(newTarget, []byte("wallpaper"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(home, "SteamWorkshop", "123")
	if err := os.MkdirAll(filepath.Dir(link), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(oldHome+"/Pictures/Wallpapers/scene.png", link); err != nil {
		t.Fatal(err)
	}

	if result := reconcileRyogamiHome(true); result.status != recWouldFix {
		t.Fatalf("check = %s %q, want would-fix", result.status.label(), result.detail)
	}
	before, err := os.ReadFile(filepath.Join(customCache, "wallpaper", "index.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(before), oldHome) {
		t.Fatal("check-only changed the catalogue")
	}

	oldService := ryogamiService
	t.Cleanup(func() { ryogamiService = oldService })
	var serviceCalls int
	ryogamiService = func([]string) int {
		serviceCalls++
		return host.ExitOK
	}
	if result := reconcileRyogamiHome(false); result.status != recFixed {
		t.Fatalf("repair = %s %q, want fixed", result.status.label(), result.detail)
	}
	if serviceCalls != 2 {
		t.Fatalf("service refresh calls = %d, want daemon-reload and try-restart", serviceCalls)
	}

	for path := range files {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(raw), oldHome) {
			t.Errorf("%s still contains old home: %s", path, raw)
		}
	}
	target, err := os.Readlink(link)
	if err != nil {
		t.Fatal(err)
	}
	if target != newTarget {
		t.Fatalf("symlink target = %q, want %q", target, newTarget)
	}
	if result := reconcileRyogamiHome(false); result.status != recOK {
		t.Fatalf("second repair = %s %q, want settled ok", result.status.label(), result.detail)
	}
}
