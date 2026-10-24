package main

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	wm "ryoku-wm"
)

// caps is the manifest every consumer gates on: the Hub hides a row its
// provider does not list, the shell picks a fallback per absent capability,
// and the reclaim reads Packages. A claim act/apply cannot keep is worse than
// an absence, so these tests pin the manifest against the code that honours it.

func TestCapsManifestIsHonestAlphabet(t *testing.T) {
	all := map[wm.Capability]bool{}
	for _, c := range wm.All() {
		all[c] = true
	}
	seen := map[wm.Capability]bool{}
	for _, c := range capsManifest {
		if !all[c] {
			t.Errorf("caps claims %q, which is not a seam capability", c)
		}
		if seen[c] {
			t.Errorf("capability %q claimed twice", c)
		}
		seen[c] = true
	}
	// The design's named absences: claiming one by accident ships a dead
	// control, so assert the list does NOT contain them.
	for _, absent := range []wm.Capability{
		wm.CapGlobalShortcuts, wm.CapPlugins, wm.CapScreenShader, wm.CapFocusGrab,
		wm.CapPersistentScreenCapture, wm.CapOutputHdr, wm.CapOutputMirror,
		wm.CapOverviewState, wm.CapOverviewBackdrop, wm.CapColumnFill,
		wm.CapCursorSet, wm.CapWorkspaceMoveToOutput,
	} {
		if seen[absent] {
			t.Errorf("caps must not claim %q on this build", absent)
		}
	}
}

// Every action gated on a claimed capability must actually run through act:
// a claimed capability whose action falls through to the unsupported error is
// the dead control this seam forbids. The stubbed request answers success for
// anything mango accepts, so an error here is the provider refusing its own
// claim. (Night-light and cursor actions spawn or rewrite the tree; those
// paths have their own tests.)
func TestClaimedActionsRun(t *testing.T) {
	home := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", home)
	t.Setenv("XDG_STATE_HOME", home)
	writeStore(t, filepath.Join(home, "ryoku", "desktop.json"), `{"desktop":{},"wm":{}}`)
	touchpadNotify = func(string, string) {}

	restore := stubRequest(t, func(cmd string) (json.RawMessage, error) {
		switch cmd {
		case "get all-monitors":
			return json.RawMessage(`{"monitors":[{"name":"eDP-1","active":true,"tags":[{"index":1,"is_active":true}]}]}`), nil
		case "get all-clients":
			return json.RawMessage(`{"clients":[{"id":4,"title":"T","appid":"a","monitor":"eDP-1","tags":[1]}]}`), nil
		case "get layouts":
			return json.RawMessage(`{"layouts":[{"symbol":"T","name":"tile"},{"symbol":"S","name":"scroller"}]}`), nil
		}
		return json.RawMessage(`{"success":true}`), nil
	})
	defer restore()

	// settings.conf must exist for the file-routed actions (layout).
	if err := runApply([]string{filepath.Join(home, "ryoku", "desktop.json")}); err != nil {
		t.Fatal(err)
	}

	for _, args := range [][]string{
		{"window.close", "4"},
		{"window.focus", "4"},
		{"window.fullscreen", "4"},
		{"window.float", "4"},
		{"window.moveToWorkspace", "4", "2"},
		{"window.summon", "T"},
		{"app.focus", "a"},
		{"workspace.focus", "2"},
		{"workspace.cycle", "1"},
		{"workspace.toggleSpecial"},
		{"workspace.layout", "2", "scroller"},
		{"output.power", "off", "eDP-1"},
		{"output.power", "on"},
		{"output.cycle"},
		{"output.enable", "eDP-1", "off"},
		{"keyboard.cycleLayout"},
		{"submap.enter", "ryoku_capture"},
		{"submap.reset"},
		{"overview.toggle"},
		{"config.reload"},
		{"decoration.borderColors", "#ff8800", "#222222"},
		{"decoration.gameMode", "on"},
		{"decoration.gameMode", "off"},
		{"input.touchpad", "off"},
		{"input.touchpad", "on"},
		{"input.focusFollowsMouse"},
		{"input.focusFollowsMouse"},
		{"session.exit"},
	} {
		err := runAct(args)
		if err != nil && (strings.Contains(err.Error(), "does not support") ||
			strings.Contains(err.Error(), "unknown action")) {
			t.Errorf("act %v refused although caps claims it: %v", args, err)
		}
		if err != nil && strings.Contains(err.Error(), "no live mango session") {
			t.Errorf("act %v saw no live session under the stub: %v", args, err)
		}
	}
}

// Packages is the reclaim contract: it must start with the variant package and
// name every satellite the variant ships. The PKGBUILD mirrors this list;
// drift between the two is the bug a switch-away reclaims nothing.
func TestPackagesLeadWithTheVariant(t *testing.T) {
	if compositorPackages[0] != "ryoku-desktop-mango" {
		t.Fatalf("reclaim must start from the variant package, got %q", compositorPackages[0])
	}
	for _, want := range []string{"mangowm", "wlr-randr", "scenefx", "xdg-desktop-portal-wlr", "wlsunset"} {
		found := false
		for _, p := range compositorPackages {
			if p == want {
				found = true
			}
		}
		if !found {
			t.Errorf("caps.Packages must list %q (the PKGBUILD depends on it)", want)
		}
	}
}

// windowRuleActions feeds the rules editor's pick list. An id listed there must
// map in windowRuleParam, or the editor offers a rule that writes nothing.
func TestWindowRuleActionsAllMap(t *testing.T) {
	for _, a := range windowRuleActions {
		param, _, reason := windowRuleParam(a, testRuleValue(a))
		if reason != "" {
			t.Errorf("rule action %q is listed but reports %q", a, reason)
		}
		if param == "" {
			t.Errorf("rule action %q is listed but emits nothing", a)
		}
	}
}

func testRuleValue(action string) string {
	switch action {
	case "size":
		return "800x600"
	case "move":
		return "10,20"
	case "workspace":
		return "3"
	case "opacity":
		return "0.8"
	}
	return ""
}
