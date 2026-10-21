package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestSwitchedDiscordThemes(t *testing.T) {
	const ours = ryokuDiscordTheme
	cases := []struct {
		name   string
		themes []string
		store  string
		want   []string
		change bool
	}{
		{"no theme gains the default", nil, "", []string{ours}, true},
		{"Midnight gives way", []string{"matugen.css"}, "", []string{ours}, true},
		{"the first Ryoku theme's place is kept", []string{"tweak.css", "matugen.css", "midnight-ryoku.theme.css"}, "", []string{"tweak.css", ours}, true},
		{"the Ryostore copy gives way", []string{"Ryoku.theme.css"}, "Ryoku.theme.css", []string{ours}, true},
		{"a theme from elsewhere stays", []string{"ClearVision.theme.css"}, "", []string{"ClearVision.theme.css"}, false},
		{"a hand-installed Ryoku theme stays", []string{"Ryoku.theme.css"}, "", []string{"Ryoku.theme.css"}, false},
		{"the shipped theme stays beside Midnight", []string{ours, "matugen.css"}, "", []string{ours, "matugen.css"}, false},
	}
	for _, c := range cases {
		got, changed := switchedDiscordThemes(c.themes, c.store)
		if changed != c.change || !slices.Equal(got, c.want) {
			t.Fatalf("%s: switchedDiscordThemes(%q, %q) = %q, %v; want %q, %v", c.name, c.themes, c.store, got, changed, c.want, c.change)
		}
	}
}

type discordFixture struct {
	home, shipped, settings, marker, receipt   string
	flatpakSettings, flatpakTheme, flatpakMark string
	instance, flatpak                          string
	retired                                    int
}

func newDiscordFixture(t *testing.T, settings string) *discordFixture {
	t.Helper()
	home, config, state := t.TempDir(), t.TempDir(), t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", config)
	t.Setenv("XDG_STATE_HOME", state)
	flatpak := filepath.Join(home, ".var", "app", vesktopFlatpakID, "config", "vesktop")
	f := &discordFixture{
		home:            home,
		shipped:         filepath.Join(config, "vesktop", "themes", ryokuDiscordTheme),
		settings:        filepath.Join(config, "vesktop", "settings", "settings.json"),
		marker:          filepath.Join(state, "ryoku", "migrations", "vesktop-ryoku-discord-theme"),
		receipt:         filepath.Join(state, "ryoku", "store", "vesktop-themes", "ryoku-discord.json"),
		flatpakSettings: filepath.Join(flatpak, "settings", "settings.json"),
		flatpakTheme:    filepath.Join(flatpak, "themes", ryokuDiscordTheme),
		flatpakMark:     filepath.Join(state, "ryoku", "migrations", "vesktop-flathub-ryoku-discord-theme"),
	}
	writeFile(t, f.shipped, "/* shipped */\n")
	writeFile(t, f.settings, settings)
	instance, flatpakInstance, remove := discordClientInstance, flatpakAppInstance, removeRyostoreDiscordTheme
	t.Cleanup(func() {
		discordClientInstance, flatpakAppInstance, removeRyostoreDiscordTheme = instance, flatpakInstance, remove
	})
	discordClientInstance = func(string, string) string { return f.instance }
	flatpakAppInstance = func(string) string { return f.flatpak }
	removeRyostoreDiscordTheme = func() error {
		f.retired++
		return os.Remove(f.receipt)
	}
	return f
}

func (f *discordFixture) themes(t *testing.T) []string {
	t.Helper()
	return discordThemesIn(t, f.settings)
}

func discordThemesIn(t *testing.T, path string) []string {
	t.Helper()
	var doc struct {
		EnabledThemes []string `json:"enabledThemes"`
	}
	if err := json.Unmarshal([]byte(readFile(t, path)), &doc); err != nil {
		t.Fatal(err)
	}
	return doc.EnabledThemes
}

func (f *discordFixture) setThemes(t *testing.T, themes ...string) {
	t.Helper()
	raw, err := json.Marshal(map[string][]string{"enabledThemes": themes})
	if err != nil {
		t.Fatal(err)
	}
	writeFile(t, f.settings, string(raw))
}

func TestDiscordThemeSwitchesOnceAndWaitsForAnOpenClient(t *testing.T) {
	f := newDiscordFixture(t, `{"useQuickCss": false, "enabledThemes": ["matugen.css"], "plugins": {"NoTrack": {"enabled": true}}, "note": "<b>"}`)
	f.instance = "41:900"

	if r := reconcileDiscordTheme(true); r.status != recWouldFix || !slices.Equal(f.themes(t), []string{"matugen.css"}) {
		t.Fatalf("check-only = %+v, themes %q; want a would-fix that leaves the file alone", r, f.themes(t))
	}
	if r := reconcileDiscordTheme(false); r.status != recFixed || !strings.Contains(r.detail, "next starts") {
		t.Fatalf("switch under an open client = %+v", r)
	}
	if got := f.themes(t); !slices.Equal(got, []string{ryokuDiscordTheme}) {
		t.Fatalf("themes after the switch = %q", got)
	}
	body := readFile(t, f.settings)
	for _, kept := range []string{`"useQuickCss": false`, `"NoTrack"`, `"note": "<b>"`} {
		if !strings.Contains(body, kept) {
			t.Fatalf("the switch rewrote more than the themes; missing %s in\n%s", kept, body)
		}
	}

	// The open instance saves its in-memory settings over the switch.
	f.setThemes(t, "matugen.css")
	if r := reconcileDiscordTheme(false); r.status != recFixed || !slices.Equal(f.themes(t), []string{ryokuDiscordTheme}) {
		t.Fatalf("a switch the open client overwrote = %+v, themes %q; want it written again", r, f.themes(t))
	}

	// Restarted, the client showed the theme, and the user went back to Midnight.
	f.instance = "52:1200"
	f.setThemes(t, "matugen.css")
	if r := reconcileDiscordTheme(false); r.status != recOK || !slices.Equal(f.themes(t), []string{"matugen.css"}) {
		t.Fatalf("a choice made after the switch = %+v, themes %q; want it left alone", r, f.themes(t))
	}
	if got := strings.TrimSpace(readFile(t, f.marker)); got != "done" {
		t.Fatalf("marker = %q, want done", got)
	}
}

func TestDiscordThemeRetiresTheRyostoreCopy(t *testing.T) {
	f := newDiscordFixture(t, `{"enabledThemes": ["Ryoku.theme.css"]}`)
	writeFile(t, f.receipt, `{"category":"vesktop-themes","id":"ryoku-discord","files":[{"destination":"Ryoku.theme.css"}]}`)

	// Open, the client still shows the store copy, so the copy stays for now.
	f.instance = "7:70"
	for range 2 {
		reconcileDiscordTheme(false)
	}
	if f.retired != 0 || !slices.Equal(f.themes(t), []string{ryokuDiscordTheme}) {
		t.Fatalf("under the open client: retired %d, themes %q; want the switch written and the copy kept", f.retired, f.themes(t))
	}

	f.instance = ""
	if r := reconcileDiscordTheme(false); r.status != recFixed || f.retired != 1 {
		t.Fatalf("closed client = %+v, retired %d; want the store copy removed", r, f.retired)
	}
	if r := reconcileDiscordTheme(false); r.status != recOK || f.retired != 1 {
		t.Fatalf("after the retirement = %+v, retired %d; want nothing left to do", r, f.retired)
	}

	// A palette bridge setup layers its Midnight base under the theme again.
	f.setThemes(t, ryokuDiscordTheme, "midnight-ryoku.theme.css")
	if r := reconcileDiscordTheme(false); r.status != recFixed || !slices.Equal(f.themes(t), []string{ryokuDiscordTheme}) {
		t.Fatalf("layered bridge Midnight = %+v, themes %q", r, f.themes(t))
	}
}

func TestDiscordThemeLeavesLinkedSettingsAlone(t *testing.T) {
	f := newDiscordFixture(t, `{}`)
	dotfile := filepath.Join(t.TempDir(), "settings.json")
	writeFile(t, dotfile, `{"enabledThemes": ["matugen.css"]}`)
	if err := os.Remove(f.settings); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(dotfile, f.settings); err != nil {
		t.Fatal(err)
	}
	if r := reconcileDiscordTheme(false); r.status != recOK || readFile(t, dotfile) != `{"enabledThemes": ["matugen.css"]}` {
		t.Fatalf("linked settings = %+v; want them untouched", r)
	}
}

func TestDiscordThemeReachesTheFlathubVesktop(t *testing.T) {
	f := newDiscordFixture(t, `{"enabledThemes": ["ryoku-discord.theme.css"]}`)

	// A Flathub Vesktop that never ran has no profile, and none is made for it.
	if r := reconcileDiscordTheme(false); r.status != recOK {
		t.Fatalf("no Flathub profile = %+v; want nothing to do", r)
	}
	if _, err := os.Stat(filepath.Join(f.home, ".var")); !os.IsNotExist(err) {
		t.Fatalf("a folder was made for a Flathub Vesktop that never ran (%v)", err)
	}

	// Its first run wrote its settings, and it is still open.
	writeFile(t, f.flatpakSettings, `{"enabledThemes": [], "useQuickCss": true}`)
	f.flatpak = "flatpak:2113"
	if r := reconcileDiscordTheme(false); r.status != recFixed || !strings.Contains(r.detail, "next starts") {
		t.Fatalf("open Flathub Vesktop = %+v; want the switch written for its next start", r)
	}
	if got := readFile(t, f.flatpakTheme); got != "/* shipped */\n" {
		t.Fatalf("Flathub copy = %q; want the shipped theme", got)
	}
	if got := discordThemesIn(t, f.flatpakSettings); !slices.Equal(got, []string{ryokuDiscordTheme}) {
		t.Fatalf("Flathub themes = %q", got)
	}

	// It closed, and an update shipped a newer theme: the copy follows it.
	f.flatpak = ""
	writeFile(t, f.shipped, "/* shipped, newer */\n")
	if r := reconcileDiscordTheme(false); r.status != recFixed || readFile(t, f.flatpakTheme) != "/* shipped, newer */\n" {
		t.Fatalf("newer shipped theme = %+v, copy %q", r, readFile(t, f.flatpakTheme))
	}
	if got := strings.TrimSpace(readFile(t, f.flatpakMark)); got != "done" {
		t.Fatalf("Flathub marker = %q, want done", got)
	}
	if r := reconcileDiscordTheme(false); r.status != recOK {
		t.Fatalf("converged = %+v; want nothing left to do", r)
	}
}

func TestDiscordThemeKeepsTheStoreCopyForAnOpenFlathubVesktop(t *testing.T) {
	f := newDiscordFixture(t, `{"enabledThemes": ["ryoku-discord.theme.css"]}`)
	writeFile(t, f.receipt, `{"category":"vesktop-themes","id":"ryoku-discord","files":[{"destination":"Ryoku.theme.css"}]}`)
	writeFile(t, f.flatpakSettings, `{"enabledThemes": ["Ryoku.theme.css"]}`)

	// The Store copied its theme into the Flathub Vesktop, which is open on it.
	f.flatpak = "flatpak:77"
	for range 2 {
		reconcileDiscordTheme(false)
	}
	if got := discordThemesIn(t, f.flatpakSettings); f.retired != 0 || !slices.Equal(got, []string{ryokuDiscordTheme}) {
		t.Fatalf("under the open Flathub Vesktop: retired %d, themes %q; want the switch written and the copy kept", f.retired, got)
	}

	f.flatpak = ""
	if r := reconcileDiscordTheme(false); r.status != recFixed || f.retired != 1 {
		t.Fatalf("closed Flathub Vesktop = %+v, retired %d; want the store copy removed", r, f.retired)
	}
}
