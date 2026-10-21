package doctor

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: Ryoku Discord theme -----------------------------------------
//
// Ryoku ships its Discord theme for Vesktop and Equibop beside Matugen's
// Midnight (matugen.css), and the settings seed turns it on in a profile the
// client has not written yet. A profile from before that is switched once: a
// theme Ryoku provided (Midnight, the palette bridge's Midnight base, the
// Ryostore copy of this theme) or no theme at all becomes the shipped one, and
// a theme picked from elsewhere stays. The switch is recorded per client, so a
// later choice made in the client stands.
//
// The client holds its settings in memory and rewrites the whole file on any
// change, so an open client takes the switch at its next start. Until that
// instance closes, a rewrite of its own that drops the switch is answered by
// writing the switch again.
//
// Fedora and Void point to the Flathub Vesktop, whose sandbox sees only its own
// ~/.var/app folder and none of ~/.config, where materialize lays the theme.
// Once that profile exists it gets the same switch, with a copy of the shipped
// theme the doctor keeps current.

const (
	ryokuDiscordTheme   = "ryoku-discord.theme.css"
	discordMidnight     = "matugen.css"
	bridgeMidnightTheme = "midnight-ryoku.theme.css"
)

// vesktopFlatpakID is the Flathub build of Vesktop.
const vesktopFlatpakID = "dev.vencord.Vesktop"

// discordProfile is one Vencord profile the theme ships for.
type discordProfile struct {
	name   string // the client, as a report names it
	marker string // the key of its one-time switch
	dir    string // the profile directory
	client string // the process an open native client runs as
	app    string // the Flathub app id, for a Flathub build
	store  bool   // whether the Ryostore copy of the theme reaches it
}

// discordProfiles are native Vesktop and Equibop under ~/.config (their
// directory there is also their process name) and the Flathub Vesktop.
func discordProfiles() []discordProfile {
	config := sys.ConfigHome()
	return []discordProfile{
		{name: "Vesktop", marker: "vesktop", dir: filepath.Join(config, "vesktop"), client: "vesktop", store: true},
		{name: "Equibop", marker: "equibop", dir: filepath.Join(config, "equibop"), client: "equibop"},
		{name: "Flathub Vesktop", marker: "vesktop-flathub", dir: filepath.Join(sys.Home(), ".var", "app", vesktopFlatpakID, "config", "vesktop"), app: vesktopFlatpakID, store: true},
	}
}

// Seams: the live box's answers, replaced in tests.
var (
	// discordClientInstance names the open instance holding a profile as
	// "<pid>:<start time>", or "" when the client is closed. Electron's
	// SingletonLock links to "<host>-<pid>"; a crash leaves the link behind,
	// naming a pid that is gone or now belongs to another program.
	discordClientInstance = func(profile, client string) string {
		target, err := os.Readlink(filepath.Join(profile, "SingletonLock"))
		if err != nil {
			return ""
		}
		proc := filepath.Join("/proc", target[strings.LastIndexByte(target, '-')+1:])
		cmdline, err := os.ReadFile(filepath.Join(proc, "cmdline"))
		if err != nil || !bytes.Contains(bytes.ToLower(cmdline), []byte(client)) {
			return ""
		}
		stat, err := os.ReadFile(filepath.Join(proc, "stat"))
		if err != nil {
			return ""
		}
		// The start time is field 22, the 20th after the parenthesised name.
		fields := strings.Fields(string(stat[bytes.LastIndexByte(stat, ')')+1:]))
		if len(fields) < 20 {
			return ""
		}
		return filepath.Base(proc) + ":" + fields[19]
	}
	// flatpakAppInstance names the running instance of a Flathub app as
	// "flatpak:<instance>", or "" when none runs. The sandbox has its own pid
	// namespace, so the SingletonLock in the app's profile names no host process.
	flatpakAppInstance = func(app string) string {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		out, err := exec.CommandContext(ctx, "flatpak", "ps", "--columns=instance,application").Output()
		if err != nil {
			return ""
		}
		for _, line := range strings.Split(string(out), "\n") {
			if fields := strings.Fields(line); len(fields) == 2 && fields[1] == app {
				return "flatpak:" + fields[0]
			}
		}
		return ""
	}
	removeRyostoreDiscordTheme = func() error {
		out, err := exec.Command("ryostore", "remove", "vesktop-themes", "ryoku-discord").CombinedOutput()
		if err != nil {
			return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
		}
		return nil
	}
)

func discordThemeMarker(client string) string {
	return filepath.Join(sys.Xdg("XDG_STATE_HOME", ".local/state"), "ryoku", "migrations", client+"-ryoku-discord-theme")
}

// ryostoreDiscordTheme is the file name of the Ryostore copy of the theme, which
// the store listed before Ryoku shipped it, or "" when that copy is not
// installed. The store's receipt is the record of what it owns.
func ryostoreDiscordTheme() string {
	raw, err := os.ReadFile(filepath.Join(sys.Xdg("XDG_STATE_HOME", ".local/state"), "ryoku", "store", "vesktop-themes", "ryoku-discord.json"))
	if err != nil {
		return ""
	}
	var receipt struct {
		Files []struct {
			Destination string `json:"destination"`
		} `json:"files"`
	}
	if json.Unmarshal(raw, &receipt) != nil {
		return ""
	}
	for _, file := range receipt.Files {
		if strings.HasSuffix(file.Destination, ".theme.css") && filepath.Base(file.Destination) == file.Destination {
			return file.Destination
		}
	}
	return ""
}

// switchedDiscordThemes is the one-time switch of a profile's enabled themes.
// The themes Ryoku provided (Midnight, the bridge's Midnight base and the
// Ryostore copy named store) give way to the shipped theme, which takes the
// first one's place, and an empty list gains it. A list that already shows the
// Ryoku theme, or only themes from elsewhere, is left as it is.
func switchedDiscordThemes(themes []string, store string) ([]string, bool) {
	for _, theme := range themes {
		if theme == ryokuDiscordTheme || (strings.EqualFold(theme, "ryoku.theme.css") && theme != store) {
			return themes, false
		}
	}
	if len(themes) == 0 {
		return []string{ryokuDiscordTheme}, true
	}
	out := make([]string, 0, len(themes))
	placed := false
	for _, theme := range themes {
		switch {
		case theme != discordMidnight && theme != bridgeMidnightTheme && (store == "" || theme != store):
			out = append(out, theme)
		case !placed:
			out = append(out, ryokuDiscordTheme)
			placed = true
		}
	}
	return out, placed
}

// replacedDiscordTheme takes name out of the enabled themes, putting the
// shipped theme in its place unless the list already shows it.
func replacedDiscordTheme(themes []string, name string) ([]string, bool) {
	i := slices.Index(themes, name)
	if i < 0 {
		return themes, false
	}
	out := slices.Clone(themes)
	if slices.Contains(themes, ryokuDiscordTheme) {
		return slices.Delete(out, i, i+1), true
	}
	out[i] = ryokuDiscordTheme
	return out, true
}

// showsRyokuTheme reports whether the enabled themes include the Ryoku theme:
// the shipped copy, or one installed under its upstream name.
func showsRyokuTheme(themes []string) bool {
	return slices.ContainsFunc(themes, func(theme string) bool {
		return theme == ryokuDiscordTheme || strings.EqualFold(theme, "ryoku.theme.css")
	})
}

// discordSettings is a client's Vencord settings file, kept as raw fields so a
// rewrite changes nothing but the enabled themes.
type discordSettings struct {
	path   string
	fields map[string]json.RawMessage
	themes []string
}

func readDiscordSettings(path string) (*discordSettings, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	s := &discordSettings{path: path}
	if json.Unmarshal(raw, &s.fields) != nil || s.fields == nil {
		return nil, fmt.Errorf("%s is not a settings object", path)
	}
	if field, ok := s.fields["enabledThemes"]; ok && json.Unmarshal(field, &s.themes) != nil {
		return nil, fmt.Errorf("%s lists its themes in an unknown form", path)
	}
	return s, nil
}

func (s *discordSettings) save(themes []string) error {
	field, err := json.Marshal(themes)
	if err != nil {
		return err
	}
	s.fields["enabledThemes"] = field
	var out bytes.Buffer
	enc := json.NewEncoder(&out)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "    ")
	if err := enc.Encode(s.fields); err != nil {
		return err
	}
	if err := writeStore(s.path, out.Bytes()); err != nil {
		return err
	}
	s.themes = themes
	return nil
}

func reconcileDiscordTheme(checkOnly bool) recResult {
	store := ryostoreDiscordTheme()
	var did []string
	kept := false
	for _, profile := range discordProfiles() {
		carried := ""
		if profile.store {
			carried = store
		}
		changes, keeps, stop := reconcileDiscordProfile(profile, carried, checkOnly)
		did = append(did, changes...)
		if stop != nil {
			return *stop
		}
		kept = kept || keeps
	}
	// Ryoku ships the theme the store copy carried, so the copy goes once no
	// profile it reaches can still be showing it.
	if store != "" && !kept {
		if checkOnly {
			did = append(did, i18n.T("the Ryostore copy of the Ryoku Discord theme would give way to the one Ryoku ships"))
		} else if err := removeRyostoreDiscordTheme(); err != nil {
			return warnRes(i18n.T("could not remove the Ryostore copy of the Ryoku Discord theme: %v"), err).
				withFix("ryostore remove vesktop-themes ryoku-discord")
		} else {
			did = append(did, i18n.T("the Ryostore copy of the Ryoku Discord theme gave way to the one Ryoku ships"))
		}
	}
	if len(did) == 0 {
		return okRes(i18n.T("Discord clients show the Ryoku theme or one you picked"))
	}
	if checkOnly {
		return wouldRes("%s", strings.Join(did, "; ")).withFix("ryoku doctor")
	}
	return fixedRes("%s", strings.Join(did, "; "))
}

// reconcileDiscordProfile converges one profile and reports what it changed,
// or would change under checkOnly. store names the Ryostore copy of the theme
// when that copy reaches the profile; keeps reports that the copy must stay
// because the profile may still be showing it. stop carries a result that ends
// the check early.
func reconcileDiscordProfile(p discordProfile, store string, checkOnly bool) (did []string, keeps bool, stop *recResult) {
	path := filepath.Join(p.dir, "settings", "settings.json")
	info, err := os.Lstat(path)
	if err != nil {
		return nil, false, nil // no profile yet: the seed covers a native one, and a Flathub build that never ran has none
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return nil, store != "", nil // linked in from elsewhere: it and the theme it shows are the user's
	}
	if p.app != "" {
		ready, changed, err := layDiscordTheme(p.dir, checkOnly)
		if err != nil {
			r := failRes(i18n.T("could not copy the Ryoku Discord theme for %s: %v"), p.name, err).withFix("ryoku doctor")
			return nil, false, &r
		}
		if !ready {
			return nil, store != "", nil // nothing to copy until materialize lays the theme
		}
		switch {
		case changed && checkOnly:
			did = append(did, i18n.Tf("%s would get the Ryoku Discord theme in its own folder", p.name))
		case changed:
			did = append(did, i18n.Tf("%s has the Ryoku Discord theme in its own folder", p.name))
		}
	} else if !sys.Exists(filepath.Join(p.dir, "themes", ryokuDiscordTheme)) {
		return nil, store != "", nil // not laid yet: switching now would enable a missing file
	}
	s, err := readDiscordSettings(path)
	if err != nil {
		r := warnRes(i18n.T("could not read the %s settings: %v"), p.name, err)
		return did, false, &r
	}
	instance := ""
	if p.app != "" {
		instance = flatpakAppInstance(p.app)
	} else {
		instance = discordClientInstance(p.dir, p.client)
	}
	marker := discordThemeMarker(p.marker)
	state := ""
	if raw, err := os.ReadFile(marker); err == nil {
		state = strings.TrimSpace(string(raw))
	}
	mark := func(value string) {
		state = value
		if !checkOnly {
			_ = os.MkdirAll(filepath.Dir(marker), 0o755)
			_ = os.WriteFile(marker, []byte(value+"\n"), 0o644)
		}
	}
	apply := func(themes []string, done, would string) *recResult {
		if checkOnly {
			s.themes = themes
			did = append(did, would)
			return nil
		}
		if err := s.save(themes); err != nil {
			r := failRes(i18n.T("could not save the %s settings: %v"), p.name, err).withFix("ryoku doctor")
			return &r
		}
		did = append(did, done)
		return nil
	}

	first := state == ""
	pendingHere := instance != "" && state == "pending "+instance
	switch {
	case first || pendingHere:
		next, changed := switchedDiscordThemes(s.themes, store)
		if changed {
			done := i18n.Tf("%s now uses the Ryoku Discord theme", p.name)
			if instance != "" {
				done = i18n.Tf("%s switches to the Ryoku Discord theme when it next starts", p.name)
			}
			if r := apply(next, done, i18n.Tf("%s would switch to the Ryoku Discord theme", p.name)); r != nil {
				return did, false, r
			}
		}
		switch {
		case changed && instance != "":
			mark("pending " + instance)
		case first:
			mark("done")
		}
	case strings.HasPrefix(state, "pending "):
		// The instance open at the switch has closed, so the client has read the
		// file since: what it shows now is the user's.
		mark("done")
	}

	// The palette bridge's Midnight base is only ever enabled by a bridge setup,
	// and layered under the Ryoku theme it changes the theme's layout.
	if i := slices.Index(s.themes, bridgeMidnightTheme); i >= 0 && showsRyokuTheme(s.themes) {
		next := slices.Delete(slices.Clone(s.themes), i, i+1)
		done := i18n.Tf("%s stops layering the palette bridge's Midnight under the Ryoku Discord theme", p.name)
		if r := apply(next, done, i18n.Tf("%s would stop layering the palette bridge's Midnight under the Ryoku Discord theme", p.name)); r != nil {
			return did, false, r
		}
	}

	// The store copy stays while an open instance may still be showing it: one
	// whose file names it, or one the switch away from it was written under.
	if store == "" {
		return did, false, nil
	}
	if instance != "" && (slices.Contains(s.themes, store) || state == "pending "+instance) {
		return did, true, nil
	}
	if next, changed := replacedDiscordTheme(s.themes, store); changed {
		if r := apply(next, i18n.Tf("%s now uses the Ryoku Discord theme", p.name), i18n.Tf("%s would switch to the Ryoku Discord theme", p.name)); r != nil {
			return did, false, r
		}
	}
	return did, false, nil
}

// layDiscordTheme keeps the shipped theme in a profile materialize does not
// reach, copied from the one it laid for native Vesktop. The file name is
// Ryoku's own, so an older copy is replaced. ready is false while there is
// nothing to copy yet; changed reports a copy written, or one checkOnly would
// write.
func layDiscordTheme(dir string, checkOnly bool) (ready, changed bool, err error) {
	shipped, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "vesktop", "themes", ryokuDiscordTheme))
	if err != nil {
		return false, false, nil
	}
	dst := filepath.Join(dir, "themes", ryokuDiscordTheme)
	if have, err := os.ReadFile(dst); err == nil && bytes.Equal(have, shipped) {
		return true, false, nil
	}
	if checkOnly {
		return true, true, nil
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return false, false, err
	}
	if err := writeStore(dst, shipped); err != nil {
		return false, false, err
	}
	return true, true, nil
}
