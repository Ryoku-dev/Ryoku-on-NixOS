package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	wm "ryoku-wm"
)

// One neutral action id in, one mango dispatch out. The only file allowed to
// spell a mango dispatcher name, which is what keeps the niri provider a
// sibling file rather than a second shell.
//
// mango dispatches over the same socket as its queries, and the reply is a
// fixed {"success":true} or an {"error":...} — an unknown function errors at
// the compositor, so act_test pins the emitted command lines.
//
// Arity is checked rather than trusted: an action arrives from a keybind or a
// script, and a mango window action without a `client,<id>` suffix silently
// applies to whatever the compositor happens to have focused.

func runAct(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("act: missing action id")
	}
	act := wm.Action(args[0])
	rest := args[1:]

	// The file-driven behaviours answer without a live session, so they run
	// before the liveness gate: apply-family verbs write the config the
	// compositor reads.
	switch act {
	case wm.ActionCursorReassert:
		// The cursor is a config block on mango: regenerating the tree is the
		// re-assert. There is no per-theme imperative call.
		return runApply([]string{storePath()})
	case wm.ActionConfigReload, wm.ActionConfigAutoreload:
		// Reload is a dispatcher both when live and when nothing answers (the
		// next login reads the tree anyway); the caller asks after apply.
		if live() {
			return dispatch("reload_config")
		}
		return nil
	}

	if !live() {
		return fmt.Errorf("act %s: no live mango session", act)
	}

	switch act {
	case wm.ActionWindowFocus:
		id, err := argID(rest, 0, "window id")
		if err != nil {
			return err
		}
		// focusid targets by IPC id through the client suffix (verified live).
		return dispatch("focusid", "client", fmt.Sprintf("%d", id))
	case wm.ActionWindowClose:
		id, err := argID(rest, 0, "window id")
		if err != nil {
			return err
		}
		return dispatch("killclient", clientSuffix(id))
	case wm.ActionWindowFullscreen:
		id, err := argID(rest, 0, "window id")
		if err != nil {
			return err
		}
		return dispatch("togglefullscreen", clientSuffix(id))
	case wm.ActionWindowFloat:
		id, err := argID(rest, 0, "window id")
		if err != nil {
			return err
		}
		return dispatch("togglefloating", clientSuffix(id))
	case wm.ActionWindowPlace:
		return placeWindow(rest)
	case wm.ActionWindowMoveToWorkspace:
		id, err := argID(rest, 0, "window id")
		if err != nil {
			return err
		}
		ws, err := arg(rest, 1, "workspace id")
		if err != nil {
			return err
		}
		tag, err := tagMask(ws)
		if err != nil {
			return err
		}
		// tag moves the window to the tag; follow it, matching what the same
		// action does on Hyprland and niri.
		return dispatch("tag", tag, clientSuffix(id))
	case wm.ActionWindowSummon:
		title, err := arg(rest, 0, "window title")
		if err != nil {
			return err
		}
		return summon(title)
	case wm.ActionAppFocus:
		appID, err := arg(rest, 0, "app id")
		if err != nil {
			return err
		}
		id, err := newestWindowOf(appID)
		if err != nil {
			return err
		}
		return dispatch("focusid", "client", fmt.Sprintf("%d", id))
	case wm.ActionWorkspaceFocus:
		ws, err := arg(rest, 0, "workspace id")
		if err != nil {
			return err
		}
		tag, err := tagMask(ws)
		if err != nil {
			return err
		}
		return dispatch("view", tag)
	case wm.ActionWorkspaceCycle:
		delta, err := arg(rest, 0, "delta")
		if err != nil {
			return err
		}
		n, convErr := strconv.Atoi(delta)
		if convErr != nil {
			return fmt.Errorf("act %s: delta must be an integer, got %q", act, delta)
		}
		switch {
		case n < 0:
			return dispatch("viewtoleft")
		case n > 0:
			return dispatch("viewtoright")
		}
		return nil
	case wm.ActionWorkspaceToggleSpecial:
		return dispatch("toggle_special_tag")
	case wm.ActionWorkspaceLayout:
		ws, err := arg(rest, 0, "workspace id")
		if err != nil {
			return err
		}
		layout, err := arg(rest, 1, "layout name")
		if err != nil {
			return err
		}
		return setTagLayout(ws, layout)
	case wm.ActionSessionExit:
		// Ryoku's sidebar already confirmed; mango's quit has no overlay.
		return dispatch("quit")
	case wm.ActionOutputPower:
		state, err := arg(rest, 0, "on|off")
		if err != nil {
			return err
		}
		if state != "on" && state != "off" {
			return fmt.Errorf("act %s: state must be on or off, got %q", act, state)
		}
		name := ""
		if len(rest) > 1 {
			name = strings.TrimSpace(rest[1])
		}
		// mango addresses one output per call. Without a name, act on every
		// output rather than guessing which one the caller meant.
		targets, err := outputNames(name)
		if err != nil {
			return err
		}
		fn := "sleep_monitor"
		if state == "on" {
			fn = "wakeup_monitor"
		}
		for _, t := range targets {
			if err := dispatch(fn, t); err != nil {
				return err
			}
		}
		return nil
	case wm.ActionKeyboardCycleLayout:
		return dispatch("switch_keyboard_layout")
	case wm.ActionSubmapEnter:
		mode, err := arg(rest, 0, "mode name")
		if err != nil {
			return err
		}
		return dispatch("setkeymode", mode)
	case wm.ActionSubmapReset:
		return dispatch("setkeymode", "default")
	case wm.ActionOverviewToggle:
		return dispatch("toggleoverview")
	case wm.ActionCursorSet:
		// theme and size arrive as config keys; rewrite settings.conf and let
		// the watched tree pick them up, then reload for the running session.
		if err := runApply([]string{storePath()}); err != nil {
			return err
		}
		return dispatch("reload_config")
	case wm.ActionBorderColors:
		return setBorderPalette(rest)
	case wm.ActionFocusFollowsMouse:
		// sloppyfocus is a scalar setoption key: flip it and print the previous
		// value so the caller can hand it back, the launcher's freeze pattern.
		return focusFollowsMouseToggle()
	case wm.ActionGameMode:
		state, err := arg(rest, 0, "on|off")
		if err != nil {
			return err
		}
		return gameMode(state)
	case wm.ActionNightLightOn:
		// -T must sit strictly above -t or wlsunset refuses the config; the
		// fixed high keeps the run pinned at the user's temperature.
		return nightlightStart("wlsunset", "-t", strconv.Itoa(nightlightTemp(rest)), "-T", "30000")
	case wm.ActionNightLightOff:
		nightlightStop("wlsunset")
		return nil
	case wm.ActionInputTouchpad:
		return touchpadAct(rest)
	case wm.ActionOutputCycle:
		return cycleOutputs()
	case wm.ActionOutputEnable:
		conn, err := arg(rest, 0, "connector")
		if err != nil {
			return err
		}
		state, err := arg(rest, 1, "on|off")
		if err != nil {
			return err
		}
		switch state {
		case "on":
			return dispatch("enable_monitor", conn)
		case "off":
			return dispatch("disable_monitor", conn)
		}
		return fmt.Errorf("act %s: state must be on or off, got %q", act, state)
	case wm.ActionScreenShader:
		return fmt.Errorf("act %s: mango has no screen shader", act)
	}

	// A known action this compositor cannot perform names the capability, so a
	// caller that skipped the gate gets told which one to check.
	if capability := act.Capability(); capability != "" {
		return fmt.Errorf("act %s: mango does not support %s", act, capability)
	}
	return fmt.Errorf("act: unknown action %q", act)
}

// placeWindow applies the neutral output-local logical rectangle to one
// specific client. Mango reports client and monitor geometry in the same global
// logical coordinate space, so only the target monitor origin is added here.
func placeWindow(args []string) error {
	id, x, y, width, height, output, err := windowPlacementArgs(args)
	if err != nil {
		return err
	}

	var clients clientsEnvelope
	if err := get("all-clients", &clients); err != nil {
		return fmt.Errorf("act %s: read windows: %w", wm.ActionWindowPlace, err)
	}
	var client *mangoClient
	for i := range clients.Clients {
		if clients.Clients[i].ID == id {
			client = &clients.Clients[i]
			break
		}
	}
	if client == nil {
		return fmt.Errorf("act %s: window id %d does not exist", wm.ActionWindowPlace, id)
	}

	var monitors monitorsEnvelope
	if err := get("all-monitors", &monitors); err != nil {
		return fmt.Errorf("act %s: read outputs: %w", wm.ActionWindowPlace, err)
	}
	var target *mangoMonitor
	for i := range monitors.Monitors {
		if monitors.Monitors[i].Name == output {
			target = &monitors.Monitors[i]
			break
		}
	}
	if target == nil {
		return fmt.Errorf("act %s: output %q does not exist", wm.ActionWindowPlace, output)
	}

	targetClient := clientSuffix(id)
	if !client.IsFloating {
		if err := dispatch("togglefloating", targetClient); err != nil {
			return fmt.Errorf("act %s: make window %d floating: %w", wm.ActionWindowPlace, id, err)
		}
	}
	if client.Monitor != output {
		if err := dispatch("tagmon", output, "1", targetClient); err != nil {
			return fmt.Errorf("act %s: move window %d to output %q: %w", wm.ActionWindowPlace, id, output, err)
		}
	}
	if err := dispatch("resizewin", strconv.Itoa(width), strconv.Itoa(height), targetClient); err != nil {
		return fmt.Errorf("act %s: resize window %d: %w", wm.ActionWindowPlace, id, err)
	}
	if err := dispatch("movewin", strconv.Itoa(target.X+x), strconv.Itoa(target.Y+y), targetClient); err != nil {
		return fmt.Errorf("act %s: position window %d: %w", wm.ActionWindowPlace, id, err)
	}
	return nil
}

func windowPlacementArgs(args []string) (id, x, y, width, height int, output string, err error) {
	id, err = argID(args, 0, "window id")
	if err != nil {
		return
	}
	names := []string{"x", "y", "width", "height"}
	values := []*int{&x, &y, &width, &height}
	for i := range values {
		raw, argErr := arg(args, i+1, names[i])
		if argErr != nil {
			err = argErr
			return
		}
		*values[i], err = strconv.Atoi(raw)
		if err != nil {
			err = fmt.Errorf("act %s: %s must be an integer, got %q", wm.ActionWindowPlace, names[i], raw)
			return
		}
	}
	if width <= 0 || height <= 0 {
		err = fmt.Errorf("act %s: width and height must be positive, got %dx%d", wm.ActionWindowPlace, width, height)
		return
	}
	output, err = arg(args, 5, "output name")
	return
}

// clientSuffix is the `client,<id>` tail that targets one window.
func clientSuffix(id int) string {
	return fmt.Sprintf("client,%d", id)
}

// tagMask validates a workspace id mango accepts: a tag number 1..tag_num, or
// 0 for the special tag. The store round-trips these as the ids watch frames
// published, so the domain is closed.
func tagMask(ws string) (string, error) {
	n, err := strconv.Atoi(strings.TrimSpace(ws))
	if err != nil || n < 0 || n > 9 {
		return "", fmt.Errorf("mango tags are numbered 0-9, got %q", ws)
	}
	return strconv.Itoa(n), nil
}

// outputNames resolves the target list for an output act: one named connector,
// or every connected output when the caller named none.
func outputNames(name string) ([]string, error) {
	var env monitorsEnvelope
	if err := get("all-monitors", &env); err != nil {
		return nil, err
	}
	if name != "" {
		for _, m := range env.Monitors {
			if m.Name == name {
				return []string{name}, nil
			}
		}
		return nil, fmt.Errorf("no such output %q", name)
	}
	out := make([]string, 0, len(env.Monitors))
	for _, m := range env.Monitors {
		out = append(out, m.Name)
	}
	return out, nil
}

// setTagLayout pins one tag's layout by rewriting the matching tagrule into
// settings.conf and reloading, the same route niri takes for config-only
// behaviour. A layout name mango does not know is refused by its own parser,
// so validate against `get layouts` first.
func setTagLayout(ws, layout string) error {
	var env layoutEnvelope
	if err := get("layouts", &env); err != nil {
		return err
	}
	ok := false
	for _, l := range env.Layouts {
		if l.Name == layout || l.Symbol == layout {
			ok = true
			layout = l.Name
			break
		}
	}
	if !ok {
		return fmt.Errorf("unknown layout %q", layout)
	}
	return rewriteTagLayout(ws, layout)
}

// focusFollowsMouseToggle flips sloppyfocus through setoption and prints the
// previous value, the exact contract ActionFocusFollowsMouse carries: the
// launcher freezes focus-follows-mouse while it is open and hands the printed
// value back on close by calling this again. mango answers no getter, and a
// live setoption leaves the generated file holding the store value, so the
// flip is recorded in a state file: absent means the live value still matches
// the file (toggle it, record what it was), present means it does not (put
// the recorded value back and report the one being left).
func focusFollowsMouseToggle() error {
	path := sloppyFocusStatePath()
	if b, err := os.ReadFile(path); err == nil {
		stored := strings.TrimSpace(string(b))
		current := "0"
		if stored == "0" {
			current = "1"
		}
		if err := dispatch("setoption", "sloppyfocus", stored); err != nil {
			return err
		}
		_ = os.Remove(path)
		fmt.Fprintln(stdout, current)
		return nil
	} else if !os.IsNotExist(err) {
		return err
	}
	current := configScalarInt("sloppyfocus", 1)
	next := 0
	if current == 0 {
		next = 1
	}
	if err := dispatch("setoption", "sloppyfocus", strconv.Itoa(next)); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(strconv.Itoa(current)+"\n"), 0o644); err != nil {
		return err
	}
	fmt.Fprintln(stdout, strconv.Itoa(current))
	return nil
}

func sloppyFocusStatePath() string {
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		dir = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(dir, "ryoku", "mango-sloppyfocus-live")
}

// gameMode strips decorations for a latency-first pass through live setoption:
// border to 0 and no shadows, restored from the store on off. The keys are all
// setoption scalars (probed live with repaint), so no config reload is needed.
func gameMode(state string) error {
	switch state {
	case "on":
		if err := dispatch("setoption", "borderpx", "0"); err != nil {
			return err
		}
		return dispatch("setoption", "shadows", "0")
	case "off":
		s := loadStore(storePath())
		if err := dispatch("setoption", "borderpx", strconv.Itoa(s.Appearance.BorderSize)); err != nil {
			return err
		}
		v := "0"
		if s.Appearance.ShadowEnabled {
			v = "1"
		}
		return dispatch("setoption", "shadows", v)
	}
	return fmt.Errorf("act decoration.gameMode: state must be on or off, got %q", state)
}

// setBorderPalette pushes the live palette's border colours into the running
// session with setoption (probed: focuscolor/bordercolor repaint immediately),
// and records them for the next apply so the generated config agrees with the
// live frame. A no-op when the store pins a fixed colour, so a wallpaper change
// never overrides a border colour the user chose.
func setBorderPalette(args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("act decoration.borderColors: want <active> <inactive>")
	}
	if !loadStore(storePath()).Appearance.BorderFollowsPalette {
		return nil
	}
	active, ok1 := mangoARGB(args[0])
	inactive, ok2 := mangoARGB(args[1])
	if !ok1 && !ok2 {
		return fmt.Errorf("act decoration.borderColors: no usable colour in %q/%q", args[0], args[1])
	}
	if ok1 {
		if err := dispatch("setoption", "focuscolor", active); err != nil {
			return err
		}
	}
	if ok2 {
		if err := dispatch("setoption", "bordercolor", inactive); err != nil {
			return err
		}
	}
	return recordBorderPalette(args[0], args[1])
}

// normBorderHex normalises a colour to "#rrggbb". ok is false for anything
// that is not six hex digits.
func normBorderHex(s string) (string, bool) {
	h := strings.TrimPrefix(strings.TrimSpace(s), "#")
	if len(h) != 6 {
		return "", false
	}
	for _, r := range h {
		if !strings.ContainsRune("0123456789abcdefABCDEF", r) {
			return "", false
		}
	}
	return "#" + strings.ToLower(h), true
}

// mangoARGB converts a store hex to mango's 0xrrggbbaa spelling.
func mangoARGB(hex string) (string, bool) {
	n, ok := normBorderHex(hex)
	if !ok {
		return "", false
	}
	return "0x" + n[1:] + "ff", true
}

var touchpadNotify = func(title, body string) {
	_ = exec.Command("notify-send", "-a", "Ryoku", title, body).Run()
}

func arg(args []string, i int, name string) (string, error) {
	if i >= len(args) || strings.TrimSpace(args[i]) == "" {
		return "", fmt.Errorf("act: missing %s", name)
	}
	return args[i], nil
}

func argID(args []string, i int, name string) (int, error) {
	raw, err := arg(args, i, name)
	if err != nil {
		return 0, err
	}
	n, convErr := strconv.Atoi(strings.TrimSpace(raw))
	if convErr != nil || n <= 0 {
		return 0, fmt.Errorf("act: %s must be a positive id, got %q", name, raw)
	}
	return n, nil
}

// summon raises an already-open window to the current tag and focuses it,
// matched by exact title. No match is an error, which lets the keybind fall
// through to launching the app.
func summon(title string) error {
	var env clientsEnvelope
	if err := get("all-clients", &env); err != nil {
		return err
	}
	var best *mangoClient
	for i := range env.Clients {
		c := &env.Clients[i]
		if c.Title != title {
			continue
		}
		if best == nil || c.ID > best.ID {
			best = c
		}
	}
	if best == nil {
		return fmt.Errorf("no window titled %q", title)
	}
	var mons monitorsEnvelope
	if err := get("all-monitors", &mons); err == nil {
		for _, m := range mons.Monitors {
			if !m.Active {
				continue
			}
			tag := activeTagIndex(m.Tags)
			if tag > 0 && !sharesTag(best.Tags, tag) {
				_ = dispatch("tag", strconv.Itoa(tag), clientSuffix(best.ID))
			}
		}
	}
	return dispatch("focusid", "client", fmt.Sprintf("%d", best.ID))
}

func sharesTag(tags []int, want int) bool {
	for _, t := range tags {
		if t == want {
			return true
		}
	}
	return false
}

// newestWindowOf resolves an app id to a window id: the highest id (mango's ids
// ascend with map order) among the matches is the most recently opened, which
// is what a caller that knows only what it launched means by "focus it".
func newestWindowOf(appID string) (int, error) {
	var env clientsEnvelope
	if err := get("all-clients", &env); err != nil {
		return 0, err
	}
	best, found := 0, false
	for _, c := range env.Clients {
		if c.AppID != appID {
			continue
		}
		if !found || c.ID > best {
			best, found = c.ID, true
		}
	}
	if !found {
		return 0, fmt.Errorf("no window from app %q", appID)
	}
	return best, nil
}

// --- touchpad ---------------------------------------------------------------

// touchpadAct locks or unlocks the touchpad the FN touchpad key drives. mango
// has a live dispatcher (toggle_trackpad_enable) but no state query for it, so
// the intent is ALSO recorded in a state file and re-emitted as
// disable_trackpad into settings.conf by writeInput — the lock survives a
// reload and the next login, and `status` answers from the file the same way
// every provider does.
func touchpadAct(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("act input.touchpad: want on|off|toggle|status|restore")
	}
	state := args[0]
	switch state {
	case "status":
		if touchpadDisabled() {
			fmt.Fprintln(stdout, "off")
		} else {
			fmt.Fprintln(stdout, "on")
		}
		return nil
	case "off":
		if err := os.MkdirAll(filepath.Dir(touchpadStatePath()), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(touchpadStatePath(), []byte("off\n"), 0o644); err != nil {
			return err
		}
		touchpadNotify("Touchpad off", "The FN key locked the touchpad. Press it again to bring it back.")
		return applyLiveTrackpad(true)
	case "on":
		if err := os.Remove(touchpadStatePath()); err != nil && !os.IsNotExist(err) {
			return err
		}
		touchpadNotify("Touchpad on", "The touchpad is unlocked.")
		return applyLiveTrackpad(false)
	case "toggle":
		if touchpadDisabled() {
			return touchpadAct([]string{"on"})
		}
		return touchpadAct([]string{"off"})
	case "restore":
		if !touchpadDisabled() {
			return nil
		}
		return applyLiveTrackpad(true)
	}
	return fmt.Errorf("act input.touchpad: want on|off|toggle|status|restore, got %q", state)
}

// applyLiveTrackpad drives the disable_trackpad config key live through
// setoption (verified: scalar reload resets it, setoption applies it) so the
// FN key bites in the running session as well as the next one. The trackpad
// docs warn some settings need a relogin; setoption is the best available
// route and the state file keeps the config honest either way.
func applyLiveTrackpad(off bool) error {
	v := "0"
	if off {
		v = "1"
	}
	if !live() {
		return nil
	}
	return dispatch("setoption", "disable_trackpad", v)
}

func touchpadStatePath() string {
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		dir = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(dir, "ryoku", "mango-touchpad-off")
}

func touchpadDisabled() bool {
	_, err := os.Stat(touchpadStatePath())
	return err == nil
}

// --- output cycle -----------------------------------------------------------

// cycleOutputs steps the arrangement one position: both on, internal only,
// external only, then back. mango has no arrangement state to read, so the
// position is kept in a state file and each step applies the on/off set with
// enable/disable_monitor. The target set is turned on before the other is
// turned off, so no step flashes every screen dark.
func cycleOutputs() error {
	var env monitorsEnvelope
	if err := get("all-monitors", &env); err != nil {
		return err
	}
	var internal, external []string
	for _, m := range env.Monitors {
		if isInternalOutput(m.Name) {
			internal = append(internal, m.Name)
		} else {
			external = append(external, m.Name)
		}
	}
	if len(internal) == 0 || len(external) == 0 {
		pos := 0
		for _, m := range env.Monitors {
			if err := dispatch("enable_monitor", m.Name); err != nil {
				return err
			}
		}
		return writeCyclePosition(pos)
	}

	pos := (readCyclePosition() + 1) % 3
	on, off := []string{}, []string{}
	switch pos {
	case 0:
		on = append(append(on, internal...), external...)
	case 1:
		on, off = internal, external
	case 2:
		on, off = external, internal
	}
	for _, n := range on {
		if err := dispatch("enable_monitor", n); err != nil {
			return err
		}
	}
	for _, n := range off {
		if err := dispatch("disable_monitor", n); err != nil {
			return err
		}
	}
	return writeCyclePosition(pos)
}

func outputCyclePath() string {
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		dir = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(dir, "ryoku", "mango-output-cycle")
}

func readCyclePosition() int {
	b, err := os.ReadFile(outputCyclePath())
	if err != nil {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		return 0
	}
	return n
}

func writeCyclePosition(pos int) error {
	if err := os.MkdirAll(filepath.Dir(outputCyclePath()), 0o755); err != nil {
		return err
	}
	return os.WriteFile(outputCyclePath(), []byte(strconv.Itoa(pos)+"\n"), 0o644)
}

// isInternalOutput tells the built-in panel from an external screen the same
// way the display tooling does.
func isInternalOutput(name string) bool {
	for _, p := range []string{"eDP", "LVDS", "DSI", "VGA-0"} {
		if strings.HasPrefix(name, p) {
			return true
		}
	}
	return false
}

// --- night light ------------------------------------------------------------

// nightlightTemp parses the colour temperature, defaulting to 4000 K and
// clamping to the range the gamma client accepts.
func nightlightTemp(args []string) int {
	if len(args) == 0 {
		return 4000
	}
	n, err := strconv.Atoi(strings.TrimSpace(args[0]))
	if err != nil || n < 1000 || n > 10000 {
		return 4000
	}
	return n
}

// nightlightStart replaces any running backend with a fresh one warmed to the
// temperature. wlsunset with no location sits at its low temperature until
// killed; the backend is detached (its own session, stdio to /dev/null) to
// outlive this short-lived invocation, and mango restores the gamma when it
// goes away (wlr-gamma-control, served — verified in src/main.c).
func nightlightStart(argv ...string) error {
	nightlightStop(argv[0])
	null, err := os.OpenFile(os.DevNull, os.O_RDWR, 0)
	if err != nil {
		return err
	}
	defer null.Close()
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = null, null, null
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	return cmd.Start()
}

// nightlightStop signals every process of this uid whose comm is name. comm
// truncates at 15 characters; the backend name fits, so exact compare is right.
func nightlightStop(name string) {
	self := os.Getuid()
	procs, err := filepath.Glob("/proc/[0-9]*")
	if err != nil {
		return
	}
	for _, p := range procs {
		comm, err := os.ReadFile(filepath.Join(p, "comm"))
		if err != nil || strings.TrimSpace(string(comm)) != name {
			continue
		}
		data, err := os.ReadFile(filepath.Join(p, "status"))
		if err != nil {
			continue
		}
		uid := -1
		for _, line := range strings.Split(string(data), "\n") {
			if rest, ok := strings.CutPrefix(line, "Uid:"); ok {
				fmt.Sscanf(strings.TrimSpace(rest), "%d", &uid)
				break
			}
		}
		if uid != self {
			continue
		}
		pid, _ := strconv.Atoi(filepath.Base(p))
		if pid > 0 {
			_ = syscall.Kill(pid, syscall.SIGTERM)
		}
	}
}
