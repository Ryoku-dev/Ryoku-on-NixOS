package main

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	wm "ryoku-wm"
)

// apply and defaults: the write half of the seam for mango. apply renders the
// neutral store into settings.conf + rebinds.conf and reports what it could not
// express; defaults hands the Hub the baseline it overlays user values on.
//
// mango can hot-reload (reload_config, verified live) but does NOT watch its
// files, so ReloadNeeded is true: the Hub's save path and `ryoku` act on it.
// With --preview apply writes nothing and only walks the store for the losses,
// which is what `ryoku wm use mango` shows a user as the cost of switching —
// and, gated on CapLiveConfigEval, doubles as the live appearance preview:
// setoption pushes the look into the running session with no file written
// (probed: focuscolor/bordercolor repaint immediately).

func runApply(args []string) error {
	preview := false
	storePath := ""
	for _, a := range args {
		if a == "--preview" {
			preview = true
			continue
		}
		if storePath == "" {
			storePath = a
		}
	}
	if storePath == "" {
		return fmt.Errorf("apply: missing store path")
	}

	s := loadStore(storePath)
	binds, bindUnhonored := genBinds(s)

	unh := unhonored(storePath)
	unh = append(unh, bindUnhonored...)

	if preview {
		if live() {
			pushEval(s)
		}
		return encodeReport(wm.ApplyReport{
			Provider:     wm.ProviderMango,
			Unhonored:    unh,
			ReloadNeeded: false,
		})
	}

	// Both generated files are always written, empty included: the shipped
	// entry sources them by name and a complete validating tree is the apply
	// contract — the same discipline the niri provider shipped under, and the
	// checkout-vs-package parity gate depends on it.
	if err := writeOverlayConf("settings.conf", genSettings(s)); err != nil {
		return err
	}
	if err := writeOverlayConf("rebinds.conf", []byte(binds)); err != nil {
		return err
	}
	rep := wm.ApplyReport{
		Provider:  wm.ProviderMango,
		Unhonored: unh,
		Written: []string{
			filepath.Join(mangoConfigDir(), "settings.conf"),
			filepath.Join(mangoConfigDir(), "rebinds.conf"),
		},
		// mango never watches its files: a config swap only bites after
		// reload_config, so the flag is the compositor's property and always
		// set — the Hyprland stance. The consumer acts on it through the
		// configReload action, which no-ops with no live session.
		ReloadNeeded: true,
	}
	return encodeReport(rep)
}

func encodeReport(rep wm.ApplyReport) error {
	enc := json.NewEncoder(stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(rep)
}

// pushEval carries a --preview store into the running session with no file
// written: the setoption scalars the Hub's sliders drive. Only keys proven
// live-settable are pushed (border colours, gaps, rounding, opacity,
// animations, master factor); everything else waits for the real apply.
func pushEval(s mangoStore) {
	a := s.Appearance
	if c := borderHex(a.ActiveBorder, a); c != "" {
		_ = dispatch("setoption", "focuscolor", c)
	}
	if c := borderHex(a.InactiveBorder, a); c != "" {
		_ = dispatch("setoption", "bordercolor", c)
	}
	_ = dispatch("setoption", "gappih", fmt.Sprint(a.GapsIn))
	_ = dispatch("setoption", "gappiv", fmt.Sprint(a.GapsIn))
	_ = dispatch("setoption", "gappoh", fmt.Sprint(a.GapsOut))
	_ = dispatch("setoption", "gappov", fmt.Sprint(a.GapsOut))
	_ = dispatch("setoption", "borderpx", fmt.Sprint(a.BorderSize))
	_ = dispatch("setoption", "border_radius", fmt.Sprint(a.Rounding))
	_ = dispatch("setoption", "focused_opacity", confNum(a.ActiveOpacity))
	_ = dispatch("setoption", "unfocused_opacity", confNum(a.InactiveOpacity))
	_ = dispatch("setoption", "animations", confBool(a.Animations))
	_ = dispatch("setoption", "default_mfact", confNum(s.Mango.DefaultMFact))
}

// borderHex resolves one border colour for the preview: the live palette file
// wins when the store follows the wallpaper, the stored colour otherwise.
func borderHex(stored string, a Appearance) string {
	if a.BorderFollowsPalette {
		if active, inactive, ok := borderPaletteColors(); ok {
			if stored == a.ActiveBorder {
				if c, ok := mangoARGB(active); ok {
					return c
				}
			} else if c, ok := mangoARGB(inactive); ok {
				return c
			}
		}
	}
	return mangoColor(stored)
}

// runDefaults prints the provider's default subtree of the neutral store.
//
// mango's `get keyboardlayout` exposes human-readable names such as
// "English (US)", not XKB identifiers such as "us". Those names are suitable
// for status displays, but must never seed desktop.input.kbLayout: the Hub
// reads this subtree as the unsaved baseline and writes it back into the
// config's xkb rule, where only an identifier is valid — so the baseline is
// the literal "us", never a probe.
func runDefaults() error {
	s := defaultStore()
	tree, err := splitStore(s)
	if err != nil {
		return err
	}
	enc := json.NewEncoder(stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(tree)
}

// unhonored names every setting the store carries that mango cannot express.
// Each desktop.* leaf gets its own short, specific reason, because that list is
// the switch cost a user reads. A foreign compositor's whole namespace collapses
// to one line, since a per-key dump of another compositor's exclusives would
// bury the losses that matter under a hundred that never mattered.
func unhonored(storePath string) []wm.Unhonored {
	ns, ok := readNeutralStore(storePath)
	if !ok {
		return nil
	}
	var out []wm.Unhonored
	out = append(out, unhonoredLeaves(ns.Desktop["appearance"], "appearance", appearanceEmitted, appearanceReason)...)
	out = append(out, unhonoredLeaves(ns.Desktop["input"], "input", inputEmitted, inputReason)...)
	out = append(out, unhonoredLeaves(ns.Desktop["cursor"], "cursor", cursorEmitted, cursorReason)...)
	out = append(out, ruleUnhonoredStored(ns.Desktop["windowRules"])...)
	out = append(out, unhonoredAppOverrides(ns.Desktop["appOverrides"])...)
	out = append(out, unhonoredDesktopMisc(ns.Desktop)...)
	out = append(out, presetProportionsUnhonored(ns)...)
	out = append(out, unhonoredForeign(ns.WM)...)
	return out
}

// ruleUnhonoredStored decodes the raw desktop.windowRules rows and reports the
// actions mango cannot express.
func ruleUnhonoredStored(raw json.RawMessage) []wm.Unhonored {
	if len(raw) == 0 {
		return nil
	}
	var rules []WindowRule
	if json.Unmarshal(raw, &rules) != nil {
		return nil
	}
	return ruleUnhonored(rules)
}

// presetProportionsUnhonored names a stored scroller preset cycle that cannot
// drive Super+R: it needs at least two proportions, and loadStore has already
// fallen back to the default so the bind still steps. Reported only when the
// user actually set fewer than two, so an unset store says nothing.
func presetProportionsUnhonored(ns neutralStore) []wm.Unhonored {
	raw, ok := ns.WM["mango"]
	if !ok {
		return nil
	}
	var m map[string]json.RawMessage
	if json.Unmarshal(raw, &m) != nil {
		return nil
	}
	stored, present := m["scrollerProportionPreset"]
	if !present {
		return nil
	}
	var p Proportions
	if json.Unmarshal(stored, &p) != nil || len(p) >= 2 {
		return nil
	}
	return []wm.Unhonored{{
		Key:    "wm.mango.scrollerProportionPreset",
		Reason: "A width cycle needs at least two proportions, so the default is used.",
	}}
}

// desktopHandled are the desktop.* keys this provider either emits or reports
// at a finer grain; a top-level key outside this set is reported whole. windows
// is honoured at runtime by the watch stream's tamer rather than the config
var desktopHandled = map[string]bool{
	"appearance": true, "input": true, "cursor": true, "env": true,
	"windowRules": true, "appOverrides": true, "autostart": true,
	"keybinds": true, "keybindRebinds": true, "unbinds": true, "apps": true,
	"windows": true,
}

var appearanceEmitted = map[string]bool{
	"gapsIn": true, "gapsOut": true, "borderSize": true, "rounding": true,
	"activeBorder": true, "inactiveBorder": true, "borderFollowsPalette": true,
	"animations": true, "activeOpacity": true, "inactiveOpacity": true,
	"shadowEnabled": true, "shadowRange": true, "shadowColor": true,
	"shadowSpread": true, "shadowOffsetX": true, "shadowOffsetY": true,
	"dimInactive": true, "dimStrength": true,
	"blurEnabled": true, "blurSize": true, "blurPasses": true,
	"blurNoise": true, "blurVibrancy": true,
}

func appearanceReason(leaf string) string {
	switch leaf {
	case "roundingPower", "shadowPower", "glowEnabled", "glowRange", "glowColor",
		"blurXray", "blurContrast", "blurBrightness", "blurSpecial", "blurPopups",
		"layout", "resizeOnBorder", "snapEnabled", "wobblyWindows", "windowStyle",
		"animatedBorder", "borderAngleSpeed", "fullscreenOpacity", "dimSpecial",
		"dimAround", "dimModal", "borderPartOfWindow":
		return "mango has no matching appearance control."
	}
	return "mango has no matching appearance control."
}

var inputEmitted = map[string]bool{
	"kbLayout": true, "kbVariant": true, "kbOptions": true, "numlockByDefault": true,
	"followMouse": true, "sensitivity": true, "accelProfile": true,
	"leftHanded": true, "mouseNaturalScroll": true, "mouseScrollFactor": true,
	"middleClickPaste": true, "naturalScroll": true, "touchScrollFactor": true,
	"tapToClick": true, "tapAndDrag": true, "clickfinger": true,
	"middleEmulation": true, "disableWhileTyping": true,
	"repeatRate": true, "repeatDelay": true,
}

func inputReason(leaf string) string {
	return "mango has no matching input control."
}

var cursorEmitted = map[string]bool{
	"theme": true, "size": true, "inactiveTimeout": true, "hideOnKeyPress": true,
}

func cursorReason(leaf string) string {
	return "mango has no matching cursor control."
}

// unhonoredAppOverrides reports each per-app override field mango cannot set.
// mango expresses opacity, radius, border, blur, shadow and animation per rule;
// dim and opaque states have no equivalent.
func unhonoredAppOverrides(raw json.RawMessage) []wm.Unhonored {
	if len(raw) == 0 {
		return nil
	}
	var overrides []AppOverride
	if json.Unmarshal(raw, &overrides) != nil {
		return nil
	}
	var out []wm.Unhonored
	for _, o := range overrides {
		name := titleName(o.Class)
		if o.Dim != "" && o.Dim != "inherit" {
			out = append(out, wm.Unhonored{
				Key:    "desktop.appOverrides." + name + ".dim",
				Reason: "mango dims every unfocused window the same way; there is no per-app dim override.",
			})
		}
		if o.Opaque != "" && o.Opaque != "inherit" {
			out = append(out, wm.Unhonored{
				Key:    "desktop.appOverrides." + name + ".opaque",
				Reason: "mango has no per-app opacity-floor override.",
			})
		}
		if o.BorderSize > 0 {
			out = append(out, wm.Unhonored{
				Key:    "desktop.appOverrides." + name + ".borderSize",
				Reason: "mango can drop a window's border but not resize it per app.",
			})
		}
		if o.Rounding > 0 {
			out = append(out, wm.Unhonored{
				Key:    "desktop.appOverrides." + name + ".rounding",
				Reason: "mango can remove a window's corner radius but not set an exact one per app.",
			})
		}
	}
	return out
}

// unhonoredLeaves reports each present leaf of a desktop.* object that mango
// does not emit, in a stable order, using reason for the user-facing why.
func unhonoredLeaves(raw json.RawMessage, section string, emitted map[string]bool, reason func(string) string) []wm.Unhonored {
	if len(raw) == 0 {
		return nil
	}
	var m map[string]json.RawMessage
	if json.Unmarshal(raw, &m) != nil {
		return nil
	}
	keys := make([]string, 0, len(m))
	for k := range m {
		if !emitted[k] {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)
	out := make([]wm.Unhonored, 0, len(keys))
	for _, k := range keys {
		out = append(out, wm.Unhonored{
			Key:    "desktop." + section + "." + k,
			Reason: reason(k),
		})
	}
	return out
}

// unhonoredDesktopMisc reports a top-level desktop.* key with no handler. A
// display-shaped key points at monitors.conf, which owns layout, so a skipped
// monitor block is visible rather than silently lost.
func unhonoredDesktopMisc(desktop map[string]json.RawMessage) []wm.Unhonored {
	var out []wm.Unhonored
	keys := make([]string, 0, len(desktop))
	for k := range desktop {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if desktopHandled[k] {
			continue
		}
		msg := "mango has no handler for this setting."
		switch k {
		case "monitors", "display", "outputs":
			msg = "monitor layout lives in monitors.conf, owned by the display tooling."
		}
		out = append(out, wm.Unhonored{Key: "desktop." + k, Reason: msg})
	}
	return out
}

// unhonoredForeign collapses each non-mango namespace that carries content into
// a single line, keyed by the namespace and derived from the store so a third
// compositor works the same way.
func unhonoredForeign(wmns map[string]json.RawMessage) []wm.Unhonored {
	var out []wm.Unhonored
	keys := make([]string, 0, len(wmns))
	for k := range wmns {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if k == wm.ProviderMango {
			continue
		}
		var m map[string]json.RawMessage
		if json.Unmarshal(wmns[k], &m) != nil || len(m) == 0 {
			continue
		}
		out = append(out, wm.Unhonored{
			Key: "wm." + k,
			Reason: titleName(k) + " settings stay saved and return when you switch back; " +
				"mango cannot apply them while it is the active compositor.",
		})
	}
	return out
}

func titleName(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return s
	}
	r := []rune(s)
	r[0] = []rune(strings.ToUpper(string(r[0])))[0]
	return string(r)
}
