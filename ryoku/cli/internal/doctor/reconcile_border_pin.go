package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
	"strings"

	i18n "ryoku-i18n"
	wm "ryoku-wm"
)

// ---- reconciler: stale window-border pin ------------------------------------
//
// The window border follows the wallpaper palette: decoration.lua reads
// ~/.cache/ryoku/hypr-colors.lua, and while colours are palette-driven the
// Hub's generated hypr/settings.lua deliberately omits col.active_border so
// the palette wins. A settings.lua generated before that rule existed (or by a
// path that once pinned fixed colours) carries a hard col.active_border
// forever, because the file only regenerates when the user changes a Hub
// setting: the palette keeps rendering fresh colours nobody applies and every
// window wears the stale pin ("the border colour is stuck on red").
//
// The provider re-emits settings.lua from the neutral store, dropping the stale
// pin when the palette drives borders, then reloads config-only. Silent when
// colours are user-fixed: a pinned border is exactly what fixed mode means.

// borderPinState is what the verdict needs, lifted so planBorderPin is pure.
type borderPinState struct {
	paletteDriven bool
	settingsLua   string // "" when the generated file is absent
	providerReady bool
}

var gatherBorderPin = func() borderPinState {
	var s borderPinState
	s.paletteDriven = themeFollowsPalette() && storeBorderFollowsPalette()
	b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "hypr", "settings.lua"))
	if err == nil {
		s.settingsLua = string(b)
	}
	s.providerReady = wm.Open().Available()
	return s
}

// themeFollowsPalette mirrors the Hub's paletteDriven(): colours come from a
// live palette when theme.json follows the wallpaper (absent file defaults to
// following, the shipped look) or shell.json locks a named static scheme.
func themeFollowsPalette() bool {
	follow := true
	if b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "ryoku", "theme.json")); err == nil {
		var t struct {
			FollowWallpaper bool `json:"followWallpaper"`
		}
		if json.Unmarshal(b, &t) == nil {
			follow = t.FollowWallpaper
		}
	}
	if follow {
		return true
	}
	if b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")); err == nil {
		var s struct {
			Theme struct {
				Theme string `json:"theme"`
			} `json:"theme"`
		}
		if json.Unmarshal(b, &s) == nil {
			switch s.Theme.Theme {
			case "", "Default", "Wallpaper":
			default:
				return true
			}
		}
	}
	return false
}

// storeBorderFollowsPalette reads desktop.appearance.borderFollowsPalette from
// the neutral store, defaulting on when the file or key is absent (the shipped
// look, where the border follows the wallpaper). A pinned border (false) is the
// chosen look even while the theme follows the wallpaper, so a col.active_border
// in settings.lua is then exactly right and the reconciler must stay silent.
func storeBorderFollowsPalette() bool {
	follow := true
	if b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "ryoku", "desktop.json")); err == nil {
		var s struct {
			Desktop struct {
				Appearance struct {
					BorderFollowsPalette *bool `json:"borderFollowsPalette"`
				} `json:"appearance"`
			} `json:"desktop"`
		}
		if json.Unmarshal(b, &s) == nil && s.Desktop.Appearance.BorderFollowsPalette != nil {
			follow = *s.Desktop.Appearance.BorderFollowsPalette
		}
	}
	return follow
}

var repairBorderPin = func() error {
	c := wm.Open()
	if _, err := c.Apply(filepath.Join(sys.ConfigHome(), "ryoku", "desktop.json")); err != nil {
		return err
	}
	// best-effort; a headless run has no compositor to reload.
	_ = c.Act(wm.ActionConfigReload, "config-only")
	return nil
}

func hasStaleBorderPin(settingsLua string) bool {
	for _, line := range strings.Split(settingsLua, "\n") {
		if strings.Contains(line, `["col.active_border"]`) && !strings.Contains(line, "wc.active") {
			return true
		}
	}
	return false
}

// planBorderPin turns observed state into a result. pure.
func planBorderPin(s borderPinState, checkOnly bool, repair func() error) recResult {
	if !s.paletteDriven {
		return okRes(i18n.T("window colours are user-fixed; a pinned border is the chosen look"))
	}
	if !hasStaleBorderPin(s.settingsLua) {
		return okRes(i18n.T("no stale border pin; the palette drives the window border"))
	}
	if !s.providerReady {
		return warnRes(i18n.T("settings.lua pins col.active_border while colours follow the palette, and no window manager provider is installed to regenerate it; the border is stuck on a stale colour")).
			withFix("ryoku update")
	}
	if checkOnly {
		return wouldRes(i18n.T("settings.lua pins col.active_border while colours follow the palette, so the window border is stuck on a stale colour")).
			withFix(i18n.T("ryoku doctor regenerates it via the provider"))
	}
	if err := repair(); err != nil {
		return failRes(i18n.T("could not regenerate settings.lua: %v"), err).
			withFix("ryoku doctor")
	}
	return fixedRes(i18n.T("regenerated settings.lua; the window border follows the palette again"))
}

func reconcileBorderPin(checkOnly bool) recResult {
	return planBorderPin(gatherBorderPin(), checkOnly, repairBorderPin)
}
