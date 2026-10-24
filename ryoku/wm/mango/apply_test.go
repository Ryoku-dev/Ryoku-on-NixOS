package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	wm "ryoku-wm"
)

// apply is the verb users feel: it must write the FULL effective config (a
// store-absent leaf keeps its default, so a fresh install boots Ryoku's look,
// never stock mango), must write both generated files even when empty, and
// must report every loss with a human reason. --preview writes nothing yet
// still answers the loss list, because that list IS the switch preview.

func sandbox(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, "state"))
	t.Setenv("HOME", home)
	t.Setenv("MANGO_INSTANCE_SIGNATURE", "")
	return home
}

func TestApplyWritesFullEffectiveConfig(t *testing.T) {
	home := sandbox(t)
	store := filepath.Join(home, ".config", "ryoku", "desktop.json")
	writeStore(t, store, `{"desktop":{"appearance":{"gapsIn":10,"gapsOut":20,"rounding":8,"blurEnabled":true,"blurSize":7}},"wm":{}}`)

	var rep wm.ApplyReport
	out := captureStdout(t, func() error { return runApply([]string{store}) })
	if err := json.Unmarshal([]byte(out), &rep); err != nil {
		t.Fatalf("apply report: %v\n%s", err, out)
	}

	settings := readGen(t, filepath.Join(home, ".config"), "settings.conf")
	for _, want := range []string{
		"gappih=10", "gappiv=10", "gappoh=20", "gappov=20",
		"border_radius=8",
		// store-absent leaves keep their defaults: the full look, not a diff.
		"borderpx=4", "focuscolor=0xe0563bff", "tag_num=9",
		"blur=1", "blur_params_radius=7",
		// the tagrules the default layout expands to
		"tagrule=id:1,layout_name:tile", "tagrule=id:9,layout_name:tile",
	} {
		if !strings.Contains(settings, want) {
			t.Errorf("settings.conf missing %q\n%s", want, settings)
		}
	}

	rebinds := readGen(t, filepath.Join(home, ".config"), "rebinds.conf")
	for _, want := range []string{
		// close keeps the iRiS confirm guard, exactly as on niri
		"bind=SUPER,q,spawn_shell," + irisCloseCheck,
		"bind=SUPER,1,view,1",
		// locked media rows emit bindl (mango's keep-live-when-locked flag)
		"bindl=NONE,XF86AudioRaiseVolume,spawn,ryoku-volume up",
		// shell surfaces reach the compositor-neutral bus
		"bind=SUPER,space,spawn,ryoku-shell launcher",
		// pointer bindings take mango's own verbs
		"mousebind=SUPER,btn_left,moveresize,curmove",
		"axisbind=SUPER,UP,viewtoleft",
	} {
		if !strings.Contains(rebinds, want) {
			t.Errorf("rebinds.conf missing %q\n%s", want, rebinds)
		}
	}

	if rep.Provider != wm.ProviderMango || len(rep.Written) != 2 {
		t.Errorf("report wrong: %+v", rep)
	}
	if !rep.ReloadNeeded {
		t.Error("mango does not watch its files; ReloadNeeded must be true")
	}

	// Both files land in the user_edits overlay too, which is how an update
	// re-lays them without resurrecting a stale copy.
	for _, name := range []string{"settings.conf", "rebinds.conf"} {
		if _, err := os.Stat(filepath.Join(home, ".config", "ryoku", "user_edits", "mango", name)); err != nil {
			t.Errorf("overlay copy %s missing: %v", name, err)
		}
	}
}

// --preview writes nothing and still walks the store for losses.
func TestApplyPreviewWritesNothingAndReports(t *testing.T) {
	home := sandbox(t)
	store := filepath.Join(home, ".config", "ryoku", "desktop.json")
	writeStore(t, store, `{"desktop":{"appearance":{"glowEnabled":true,"wobblyWindows":true}},"wm":{"hyprland":{"enabled":true,"plugins":{"x":1}}}}`)

	var rep wm.ApplyReport
	out := captureStdout(t, func() error { return runApply([]string{store, "--preview"}) })
	if err := json.Unmarshal([]byte(out), &rep); err != nil {
		t.Fatalf("preview report: %v\n%s", err, out)
	}

	if rep.Written != nil {
		t.Errorf("preview must write nothing, wrote %v", rep.Written)
	}
	if _, err := os.Stat(filepath.Join(home, ".config", "mango", "settings.conf")); err == nil {
		t.Error("preview created settings.conf")
	}

	keys := map[string]bool{}
	for _, u := range rep.Unhonored {
		keys[u.Key] = true
	}
	// Per-leaf reasons for what mango cannot do.
	for _, want := range []string{
		"desktop.appearance.glowEnabled",
		"desktop.appearance.wobblyWindows",
	} {
		if !keys[want] {
			t.Errorf("preview must report %q; got %v", want, keys)
		}
	}
	// A foreign compositor's whole namespace collapses to ONE aggregated
	// line, never per key: a real store has ~100 rows and would bury the
	// losses that matter.
	foreign := 0
	for k := range keys {
		if strings.HasPrefix(k, "wm.hyprland") {
			foreign++
		}
	}
	if foreign != 1 || !keys["wm.hyprland"] {
		t.Errorf("want one aggregated wm.hyprland line, got %d: %v", foreign, keys)
	}
	for _, u := range rep.Unhonored {
		if u.Reason == "" {
			t.Errorf("unhonored %q carries no user reason", u.Key)
		}
	}
}

// A store carried from another compositor must name each desktop.* loss with
// its own reason, so the switch preview reads as a cost, not a mystery.
func TestUnhonoredNamesEveryLoss(t *testing.T) {
	ns := neutralStore{Desktop: map[string]json.RawMessage{
		"appearance": json.RawMessage(`{"glowEnabled":true,"shadowPower":2,"layout":"dwindle","fullscreenOpacity":0.9}`),
		"input":      json.RawMessage(`{"mouseScrollMethod":"edge"}`),
		"cursor":     json.RawMessage(`{"warpOnFocus":"never"}`),
		"monitors":   json.RawMessage(`{"eDP-1":{"mode":"1920x1080"}}`),
	}}
	b, _ := json.Marshal(ns)
	dir := t.TempDir()
	store := filepath.Join(dir, "desktop.json")
	if err := os.WriteFile(store, b, 0o644); err != nil {
		t.Fatal(err)
	}
	out := unhonored(store)
	have := map[string]string{}
	for _, u := range out {
		have[u.Key] = u.Reason
	}
	for _, want := range []string{
		"desktop.appearance.glowEnabled", "desktop.appearance.shadowPower",
		"desktop.appearance.layout", "desktop.appearance.fullscreenOpacity",
		"desktop.input.mouseScrollMethod", "desktop.cursor.warpOnFocus",
		"desktop.monitors",
	} {
		if _, ok := have[want]; !ok {
			t.Errorf("loss %q not reported: %v", want, have)
		}
	}
	// The display-shaped key points at the file that owns layout.
	if !strings.Contains(have["desktop.monitors"], "monitors.conf") {
		t.Errorf("monitors loss should name monitors.conf, got %q", have["desktop.monitors"])
	}
}

// The layout master keeps the tag's current layout when only another field of
// the tagrule changes, and a missing tagrule row is appended, not lost.
func TestRewriteTagLayoutKeepsSiblings(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	body := "tag_num=9\ntagrule=id:1,layout_name:tile,nmaster:2\ntagrule=id:2,layout_name:tile\n"
	if err := os.MkdirAll(filepath.Join(dir, "mango"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "mango", "settings.conf"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	restore := stubRequest(t, func(string) (json.RawMessage, error) {
		return json.RawMessage(`{"success":true}`), nil
	})
	defer restore()

	if err := rewriteTagLayout("1", "scroller"); err != nil {
		t.Fatal(err)
	}
	got := string(readGenRaw(t, filepath.Join(dir, "mango", "settings.conf")))
	if !strings.Contains(got, "tagrule=id:1,layout_name:scroller,nmaster:2") {
		t.Errorf("layout replaced but siblings lost:\n%s", got)
	}
	if !strings.Contains(got, "tagrule=id:2,layout_name:tile") {
		t.Errorf("untouched tagrule lost:\n%s", got)
	}

	if err := rewriteTagLayout("9", "deck"); err != nil {
		t.Fatal(err)
	}
	got = string(readGenRaw(t, filepath.Join(dir, "mango", "settings.conf")))
	if !strings.Contains(got, "tagrule=id:9,layout_name:deck") {
		t.Errorf("missing tagrow should be appended:\n%s", got)
	}
}

func readGenRaw(t *testing.T, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// defaults is the Hub's baseline subtree. Its shape is the store codec's
// contract: desktop.* flat, wm.mango.* the exclusives.
func TestDefaultsShape(t *testing.T) {
	var tree map[string]json.RawMessage
	out := captureStdout(t, func() error { return runDefaults() })
	if err := json.Unmarshal([]byte(out), &tree); err != nil {
		t.Fatal(err)
	}
	var desktop map[string]any
	json.Unmarshal(tree["desktop"], &desktop)
	for _, want := range []string{"appearance", "input", "cursor", "windows", "env", "windowRules", "appOverrides", "autostart", "keybinds"} {
		if _, ok := desktop[want]; !ok {
			t.Errorf("defaults desktop.%s missing", want)
		}
	}
	var wmns map[string]json.RawMessage
	json.Unmarshal(tree["wm"], &wmns)
	if _, ok := wmns["mango"]; !ok {
		t.Fatal("defaults must seed the wm.mango namespace")
	}
	// kbLayout is the literal identifier, never a probe: the Hub writes this
	// back into the config's xkb rule, where "English (US)" would be fatal.
	var appear struct {
		Input struct {
			KbLayout string `json:"kbLayout"`
		} `json:"input"`
	}
	_ = json.Unmarshal(tree["desktop"], &appear)
	if appear.Input.KbLayout != "us" {
		t.Errorf("baseline kbLayout = %q, want the us identifier", appear.Input.KbLayout)
	}
}

// Every wm.mango.* row the Hub shows must name a real store leaf, or the row
// is a dead control: the draft writes a key nothing reads back. This walks the
// embedded schema against the defaults subtree, which is the same pair the Hub
// renders side by side.
func TestSchemaRowsRoundTripTheStore(t *testing.T) {
	rows, err := loadSchemaRows()
	if err != nil {
		t.Fatal(err)
	}
	var tree map[string]json.RawMessage
	out := captureStdout(t, func() error { return runDefaults() })
	if err := json.Unmarshal([]byte(out), &tree); err != nil {
		t.Fatal(err)
	}
	var wmns map[string]json.RawMessage
	if err := json.Unmarshal(tree["wm"], &wmns); err != nil {
		t.Fatal(err)
	}
	var mango map[string]json.RawMessage
	if err := json.Unmarshal(wmns["mango"], &mango); err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for _, raw := range rows {
		var r struct {
			Key string `json:"key"`
		}
		if err := json.Unmarshal(raw, &r); err != nil {
			t.Fatal(err)
		}
		if !strings.HasPrefix(r.Key, "wm.mango.") {
			continue
		}
		leaf := strings.TrimPrefix(r.Key, "wm.mango.")
		top := leaf
		if i := strings.IndexByte(leaf, '.'); i >= 0 {
			top = leaf[:i]
		}
		if _, ok := mango[top]; !ok {
			t.Errorf("schema row %s names no store leaf", r.Key)
		}
		seen[r.Key] = true
	}
	if len(seen) < 90 {
		t.Errorf("expected the full customisation surface, saw %d rows", len(seen))
	}
}

// The customisation keys the Hub can now drive must actually reach the
// generated file, in mango's own spellings, and a user value must beat the
// baseline. This is the contract behind every new row.
func TestCustomisationKeysEmitAndOverride(t *testing.T) {
	home := sandbox(t)
	store := filepath.Join(home, ".config", "ryoku", "desktop.json")
	writeStore(t, store, `{"desktop":{},"wm":{"mango":{
		"tagCarousel":true,"snapDistance":64,"dragCorner":"1",
		"dwindleSplitRatio":0.62,"rootColor":"#10203040",
		"mouseScrollMethod":"2","layerAnimationTypeOpen":"fade",
		"specialDim":0.25,"gestureLive":false}}}`)

	out := captureStdout(t, func() error { return runApply([]string{store}) })
	if strings.Contains(out, `"key": "wm.mango.`) {
		t.Errorf("new wm.mango leaves must not be reported unhonored:\n%s", out)
	}
	settings := readGen(t, filepath.Join(home, ".config"), "settings.conf")
	for _, want := range []string{
		"tag_carousel=1", "snap_distance=64", "drag_corner=1",
		"dwindle_split_ratio=0.62", "rootcolor=0x10203040",
		"mouse_scroll_method=2", "layer_animation_type_open=fade",
		"special_dim=0.25", "gesture_live=0",
		// untouched leaves keep mango's compiled baseline
		"tag_gather=0", "enable_floating_snap=0", "hotarea_corner=2",
		"single_scratchpad=1", "scroller_prefer_overspread=1",
		"overcircle_center_ratio=0.5", "button_map=0",
		"touch_enable=1", "zoom_end_ratio=0.8",
	} {
		if !strings.Contains(settings, want) {
			t.Errorf("settings.conf missing %q\n%s", want, settings)
		}
	}
}
