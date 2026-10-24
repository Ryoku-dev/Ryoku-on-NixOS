package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeThemeFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func themeEnv(t *testing.T) (cfg, cache, state string) {
	t.Helper()
	root := t.TempDir()
	cfg, cache, state = filepath.Join(root, "config"), filepath.Join(root, "cache"), filepath.Join(root, "state")
	t.Setenv("XDG_CONFIG_HOME", cfg)
	t.Setenv("XDG_CACHE_HOME", cache)
	t.Setenv("XDG_STATE_HOME", state)
	return
}

func TestThemeResolvesLikeTheDesktop(t *testing.T) {
	cases := []struct {
		name       string
		shell      string
		themeJSON  string
		colors     string
		wantSource string
		want       map[string]string
	}{
		{
			name:       "nothing on disk paints the signature defaults",
			wantSource: "default",
			want:       map[string]string{"surface": "#000000", "onSurface": "#cdc4ba", "primary": "#e2342a"},
		},
		{
			name:       "the wallpaper palette follows by default",
			colors:     `{"surface":"#1a1111","onSurface":"#f0dedd","primary":"#ffb3b1"}`,
			wantSource: "wallpaper",
			want:       map[string]string{"surface": "#1a1111", "onSurface": "#f0dedd", "primary": "#ffb3b1", "inverseSurface": "#cdc4ba"},
		},
		{
			name:       "a named scheme beats the wallpaper",
			shell:      `{"themePalette":{"surface":"#101010","primary":"#88c0d0"}}`,
			colors:     `{"surface":"#1a1111","primary":"#ffb3b1","onSurface":"#f0dedd"}`,
			wantSource: "scheme",
			want:       map[string]string{"surface": "#101010", "primary": "#88c0d0", "onSurface": "#f0dedd"},
		},
		{
			name:       "follow wallpaper off ignores colors.json",
			themeJSON:  `{"followWallpaper":false}`,
			colors:     `{"surface":"#1a1111"}`,
			wantSource: "default",
			want:       map[string]string{"surface": "#000000"},
		},
		{
			name:       "a half-written role falls through instead of painting black",
			colors:     `{"surface":"","onSurface":null,"primary":"#ffb3b1"}`,
			wantSource: "wallpaper",
			want:       map[string]string{"surface": "#000000", "onSurface": "#cdc4ba", "primary": "#ffb3b1"},
		},
		{
			name:       "an unreadable colors.json falls back to defaults",
			colors:     `{"surface":`,
			wantSource: "default",
			want:       map[string]string{"surface": "#000000"},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			cfg, cache, _ := themeEnv(t)
			if c.shell != "" {
				writeThemeFile(t, filepath.Join(cfg, "ryoku", "shell.json"), c.shell)
			}
			if c.themeJSON != "" {
				writeThemeFile(t, filepath.Join(cfg, "ryoku", "theme.json"), c.themeJSON)
			}
			if c.colors != "" {
				writeThemeFile(t, filepath.Join(cache, "ryoku", "colors.json"), c.colors)
			}
			th := ThemeNow()
			if th.Source != c.wantSource {
				t.Errorf("source = %q, want %q", th.Source, c.wantSource)
			}
			for k, v := range c.want {
				if th.Roles[k] != v {
					t.Errorf("%s = %q, want %q", k, th.Roles[k], v)
				}
			}
		})
	}
}

func TestCurrentWallpaperOnlyServesKnownFiles(t *testing.T) {
	_, _, state := themeEnv(t)
	dir := t.TempDir()
	img := filepath.Join(dir, "wall.JPG")
	clip := filepath.Join(dir, "live.mp4")
	secret := filepath.Join(dir, "id_ed25519")
	for _, p := range []string{img, clip, secret} {
		writeThemeFile(t, p, "x")
	}
	cases := []struct {
		name, record, wantKind string
		wantOK                 bool
	}{
		{"an image is served as an image", img + "\n", "image", true},
		{"a live wallpaper is served as video", clip, "video", true},
		{"a file that is not a wallpaper is refused", secret, "", false},
		{"a missing file is refused", filepath.Join(dir, "gone.png"), "", false},
		{"a directory is refused", dir + "/", "", false},
		{"an empty record is refused", "\n", "", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			writeThemeFile(t, filepath.Join(state, "ryoku-wallpaper"), c.record)
			_, kind, ok := CurrentWallpaper()
			if ok != c.wantOK || kind != c.wantKind {
				t.Errorf("got (%q, %v), want (%q, %v)", kind, ok, c.wantKind, c.wantOK)
			}
		})
	}
}
