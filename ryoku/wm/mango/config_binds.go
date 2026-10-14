package main

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	wm "ryoku-wm"
)

// The mango binds block. mango warns on a duplicate chord and keeps the LAST
// definition (measured on a live instance), so a stray collision degrades
// silently rather than failing: rebinds.conf must therefore be the sole, total
// source of binds, one winner per chord — custom over rebound default over
// static default — exactly the discipline niri's hard error forced. This file
// translates the shipped Ryoku catalogue (ryoku/wm/binds.go) into mango's own
// dispatchers and folds the store's rebinds, unbinds and customs into it.
// binds reports the resolved legend; apply writes it.

// mangoBind is how mango expresses one catalogue entry: the mango command tail
// (everything after the chord in a bind= line), or a reason when mango has no
// action for the behaviour (which lists the bind as an unhonored legend row
// rather than dropping it). kind overrides the emitted verb (bindl for locked,
// axisbind for wheel, mousebind for buttons). label and hint replace the
// catalogue copy when mango's mechanic differs. In a family command, {n} is
// the tag number, substituted per expanded chord.
type mangoBind struct {
	cmd    string
	kind   string // "", "bindl", "axisbind", "mousebind"
	reason string
	label  string
	hint   string
}

// A bind-spawned qs surface never passes through ryoku-shell's daemon, which is
// what injects the shared QML module path into the configs it supervises.
// irisCloseCheck succeeds when the iRiS frame is the bar style and its close
// confirmation is switched on.
const irisCloseCheck = `jq -e '(.barStyle // "qsbar") == "iris" and .inir.closeConfirm.enabled == true' "${XDG_CONFIG_HOME:-$HOME/.config}/ryoku/shell.json" >/dev/null 2>&1`

const qmlEnv = `env QML_IMPORT_PATH="$HOME/.local/lib/qt6/qml" QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml"`

// defaultBinds maps each catalogue id to mango's expression of it. Compositor
// behaviours become mango dispatchers; app and shell launches spawn the same
// commands (shell surfaces go through ryoku-shell, whose openSurface bus is
// compositor agnostic); mango's native overview takes the workspace overview.
// Behaviours mango cannot perform (workspace reorder, inhibit toggle) carry a
// reason so the legend reports them instead of hiding them. An id absent here
// is left off entirely, which would be a bug, so the tests assert full
// coverage.
func defaultBinds() map[string]mangoBind {
	return map[string]mangoBind{
		// Windows. The iRiS frame can ask before a window closes; only when
		// that is on and iRiS is the bar style does the close go through the
		// shell, else it falls back to the compositor's own kill.
		"window.close":         {cmd: "spawn_shell," + irisCloseCheck + " && qs -c shell ipc call closeConfirm trigger || mmsg dispatch killclient"},
		"window.fullscreen":    {cmd: "togglefullscreen"},
		"window.float":         {cmd: "togglefloating"},
		"window.pin":           {cmd: "toggleglobal"},
		"window.resize":        {cmd: "switch_proportion_preset", label: "Step column width", hint: "Cycle the window through its preset widths"},
		"window.presetHeight":  {reason: "mango has no window height presets."},
		"column.tabbed":        {reason: "mango groups windows instead of tabbing a column."},
		"column.maximize":      {cmd: "togglemaximizescreen"},
		"column.center":        {cmd: "centerwin"},
		"window.focusPrevious": {cmd: "focuslast"},

		// Focus
		"focus.left":   {cmd: "focusdir,left"},
		"focus.right":  {cmd: "focusdir,right"},
		"focus.up":     {cmd: "focusdir,up"},
		"focus.down":   {cmd: "focusdir,down"},
		"column.first": {reason: "mango has no first-column jump."},
		"column.last":  {reason: "mango has no last-column jump."},

		// Move
		"move.left":         {cmd: "move_client,left"},
		"move.right":        {cmd: "move_client,right"},
		"move.up":           {cmd: "move_client,up"},
		"move.down":         {cmd: "move_client,down"},
		"column.mergeLeft":  {cmd: "groupjoin,left", label: "Group left", hint: "Join the window into the group on the left"},
		"column.mergeRight": {cmd: "groupjoin,right", label: "Group right", hint: "Join the window into the group on the right"},

		// Resize. Tile layouts step the master split; free resize handles the
		// height steps.
		"resize.narrower":    {cmd: "setmfact,-0.05"},
		"resize.wider":       {cmd: "setmfact,+0.05"},
		"resize.shorter":     {cmd: "resizewin,+0,-50"},
		"resize.taller":      {cmd: "resizewin,+0,+50"},
		"resize.resetHeight": {reason: "mango has no automatic height to give back."},

		// Workspaces. The families carry {n}, the tag number. The Ryoku model
		// numbers ten slots; mango runs nine (tag_num=9) and its tenth, the
		// special tag, is not addressable through the digit mask (measured on a
		// live instance), so resolveBinds skips and reports the tenth chord.
		"workspace.focus":                   {cmd: "view,{n}"},
		"workspace.moveWindow":              {cmd: "tag,{n}"},
		"workspace.moveWindowSilent":        {cmd: "tagsilent,{n}"},
		"workspace.focus.numpad":            {cmd: "view,{n}"},
		"workspace.moveWindow.numpad":       {cmd: "tag,{n}"},
		"workspace.moveWindowSilent.numpad": {cmd: "tagsilent,{n}"},
		"workspace.prev":                    {cmd: "viewtoleft"},
		"workspace.next":                    {cmd: "viewtoright"},
		"workspace.prevWheel":               {cmd: "viewtoleft", kind: "axisbind"},
		"workspace.nextWheel":               {cmd: "viewtoright", kind: "axisbind"},
		"workspace.moveWindowPrev":          {cmd: "tagtoleft"},
		"workspace.moveWindowNext":          {cmd: "tagtoright"},
		"workspace.reorderUp":               {reason: "mango tags are fixed slots with nothing to reorder."},
		"workspace.reorderDown":             {reason: "mango tags are fixed slots with nothing to reorder."},
		"workspace.hideWindow":              {cmd: "minimized"},
		"workspace.scratchpad":              {cmd: "toggle_scratchpad"},
		"workspace.overview":                {cmd: "toggleoverview"},
		"workspace.overviewDesktops":        {reason: "mango has no desktop blocks to step through."},

		// Displays
		"display.focus.left":          {cmd: "focusmon,left"},
		"display.focus.right":         {cmd: "focusmon,right"},
		"display.focus.up":            {cmd: "focusmon,up"},
		"display.focus.down":          {cmd: "focusmon,down"},
		"display.moveWindow.left":     {cmd: "tagmon,left"},
		"display.moveWindow.right":    {cmd: "tagmon,right"},
		"display.moveWindow.up":       {cmd: "tagmon,up"},
		"display.moveWindow.down":     {cmd: "tagmon,down"},
		"display.moveWorkspace.left":  {reason: "mango tags live on one monitor and cannot move."},
		"display.moveWorkspace.right": {reason: "mango tags live on one monitor and cannot move."},
		"display.moveWorkspace.up":    {reason: "mango tags live on one monitor and cannot move."},
		"display.moveWorkspace.down":  {reason: "mango tags live on one monitor and cannot move."},
		"display.cycle":               {cmd: "spawn,ryoku-wm-mango act output.cycle"},

		// Apps
		"app.terminal": {cmd: "spawn,ryoku-app terminal"},
		"app.files":    {cmd: "spawn,ryoku-app files"},
		"app.browser":  {cmd: "spawn,ryoku-app browser"},
		"app.editor":   {cmd: "spawn,ryoku-app editor"},
		"app.notes":    {cmd: "spawn,ryoku-app notes"},
		"app.yazi":     {cmd: "spawn,kitty -e yazi"},
		"app.ryotunes": {cmd: "spawn,ryotunes"},

		// Shell. Surfaces reach the compositor-agnostic ryoku-shell bus; the qs
		// surfaces bind exactly as they do on niri.
		"shell.launcher":          {cmd: "spawn,ryoku-shell launcher"},
		"shell.ask":               {cmd: "spawn,ryoku-shell ask"},
		"shell.rashin":            {cmd: "spawn_shell,ryoku-summon Rashin flock -n -o /tmp/rashin-app.lock rashin-app"},
		"shell.cheatsheet":        {cmd: "spawn_shell,pkill -x -f 'qs -c keys' 2>/dev/null || " + qmlEnv + " flock -n -o /tmp/ryoku-keys.lock qs -c keys"},
		"shell.lock":              {cmd: "spawn,ryoku-shell lock"},
		"shell.quicksettings":     {cmd: "spawn,ryoku-shell quicksettings"},
		"shell.wallpaper":         {cmd: "spawn,ryogami wallpaper ui"},
		"shell.wallpaperRandom":   {cmd: "spawn,ryogami wallpaper random"},
		"shell.ryovm":             {cmd: "spawn_shell,ryoku-summon ryovm " + qmlEnv + " flock -n -o /tmp/ryovm.lock qs -c ryovm"},
		"shell.clipboard":         {cmd: "spawn,ryoku-shell clipboard"},
		"shell.visualizer":        {cmd: "spawn,ryoku-shell visualizer"},
		"shell.visualizerOverlay": {cmd: "spawn,ryoku-shell visualizer-overlay"},
		"shell.visualizerPlace":   {cmd: "spawn,ryoku-shell visualizer-place"},
		"shell.voice":             {cmd: "spawn,ryoku-shell voice"},
		"shell.settings":          {cmd: "spawn,ryoku-shell hub open"},
		"shell.screenshot":        {cmd: "spawn_shell," + qmlEnv + " flock -n -o /tmp/ryoshot.lock qs -c ryoshot"},
		"shell.screenshotPrint":   {cmd: "spawn_shell," + qmlEnv + " flock -n -o /tmp/ryoshot.lock qs -c ryoshot"},
		"shell.screenshotMonitor": {cmd: "spawn_shell," + qmlEnv + " flock -n -o /tmp/ryoshot.lock env RYOSHOT_MODE=monitor qs -c ryoshot"},
		"shell.colorPicker":       {cmd: "spawn,hyprpicker -a"},
		"shell.restartAudio":      {cmd: "spawn,ryoku-restart-audio"},
		"shell.inhibitShortcuts":  {reason: "mango has no shortcuts-inhibit toggle."},

		// Media. Locked in the catalogue, so the rows emit bindl: mango's `l`
		// flag keeps the chord live while the session is locked (verified
		// against the shipped config grammar).
		"media.volumeUp":   {cmd: "spawn,ryoku-volume up", kind: "bindl"},
		"media.volumeDown": {cmd: "spawn,ryoku-volume down", kind: "bindl"},
		"media.mute":       {cmd: "spawn,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", kind: "bindl"},
		"media.micMute":    {cmd: "spawn,wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", kind: "bindl"},
		"media.play":       {cmd: "spawn,playerctl play-pause", kind: "bindl"},
		"media.next":       {cmd: "spawn,playerctl next", kind: "bindl"},
		"media.prev":       {cmd: "spawn,playerctl previous", kind: "bindl"},

		// Hardware
		"hardware.brightnessUp":   {cmd: "spawn,ryoku-cmd-brightness +5", kind: "bindl"},
		"hardware.brightnessDown": {cmd: "spawn,ryoku-cmd-brightness -5", kind: "bindl"},
		"hardware.touchpadToggle": {cmd: "spawn,ryoku-wm-mango act input.touchpad toggle", kind: "bindl"},
		"hardware.touchpadOn":     {cmd: "spawn,ryoku-wm-mango act input.touchpad on", kind: "bindl"},
		"hardware.touchpadOff":    {cmd: "spawn,ryoku-wm-mango act input.touchpad off", kind: "bindl"},

		// Mouse. mango's moveresize dispatcher is the exact neutral behaviour.
		"mouse.move":   {cmd: "moveresize,curmove", kind: "mousebind"},
		"mouse.resize": {cmd: "moveresize,curresize", kind: "mousebind"},
	}
}

// outBind is one resolved bind, ready for the config writer: the verb to emit,
// the mango modifier and key fields, and the command tail.
type outBind struct {
	mods, key, cmd, verb string
}

// resolveBinds expands the catalogue into the emitted bind set and folds the
// store's custom binds, rebinds and unbinds into it, resolving every chord to
// one winner: a custom bind beats a rebound default beats a static default. A
// family expands to its ten chords; the tenth (the 0 key) names mango's
// special tag, which the digit mask does not address, so it is skipped and
// reported once per family. It is the single source genBinds writes, so the
// emitted config never carries a chord twice. report names each behaviour
// mango could not honour.
func resolveBinds(s mangoStore) ([]outBind, []wm.Unhonored) {
	type entry struct {
		b    outBind
		rank int // higher wins a chord collision
	}
	defs := defaultBinds()
	seen := map[string]entry{}
	var order []string
	var report []wm.Unhonored
	tenReported := map[string]bool{}

	add := func(chord string, e entry) {
		key := wm.NormChord(chord)
		if prev, ok := seen[key]; ok && prev.rank >= e.rank {
			return
		}
		if _, fresh := seen[key]; !fresh {
			order = append(order, key)
		}
		seen[key] = e
	}

	unbinds := map[string]bool{}
	for _, u := range s.Unbinds {
		unbinds[wm.NormChord(u)] = true
	}

	for _, cb := range wm.ShippedBinds() {
		mb, mapped := defs[cb.ID]
		if !mapped {
			continue // test coverage asserts every catalogue id is mapped
		}
		if mb.reason != "" {
			report = append(report, wm.Unhonored{Key: "bind." + cb.ID, Reason: mb.reason})
			continue
		}
		defChord := cb.Chord
		rebounded := false
		if cb.Family {
			if rc, ok := wm.FamilyRebind(defChord, s.KeybindRebinds); ok {
				defChord, rebounded = rc, true
			}
		} else if v, ok := effectiveChord(defChord, s.KeybindRebinds); ok {
			defChord, rebounded = v, true
		}
		if unbinds[wm.NormChord(defChord)] {
			continue
		}
		rank := 1
		if rebounded {
			rank = 2
		}
		chords := []string{defChord}
		if cb.Family {
			var expanded []string
			for n := 1; n <= 10; n++ {
				expanded = append(expanded, wm.ExpandChord(defChord, n))
			}
			chords = expanded
		}
		for _, chord := range chords {
			tag := tagOfChord(chord)
			if cb.Family && tag == "0" {
				if !tenReported[cb.ID] {
					tenReported[cb.ID] = true
					report = append(report, wm.Unhonored{
						Key: "bind." + cb.ID + ".10",
						Reason: "mango numbers tags 1-9; its tenth slot is the special tag, " +
							"which the number keys do not address.",
					})
				}
				continue
			}
			mangoCmd := strings.ReplaceAll(mb.cmd, "{n}", tag)
			verb, mods, key, ok := toMangoChord(chord, mb.kind)
			if !ok {
				report = append(report, wm.Unhonored{
					Key:    "bind." + cb.ID,
					Reason: "mango cannot bind " + chord + ".",
				})
				continue
			}
			add(chord, entry{b: outBind{mods: mods, key: key, cmd: mangoCmd, verb: verb}, rank: rank})
		}
	}

	for _, k := range s.Keybinds {
		if strings.TrimSpace(k.Keys) == "" {
			continue
		}
		cmd, reason := customCommand(k)
		verb := "bind"
		if k.Release {
			verb = "bindr"
		}
		mods, raw, ok := toMangoParts(k.Keys)
		key, keyOK := "", false
		if ok {
			key, keyOK = mangoKey(raw)
		}
		if keyOK && reason == "" && cmd != "" {
			// mango reads one config line into a 255-byte value buffer and
			// truncates silently, so a command whose whole chord tail does not
			// fit is reported, never emitted half a line.
			if len(mods)+len(key)+len(cmd)+2 > 255 {
				report = append(report, wm.Unhonored{
					Key: "bind.custom." + k.Keys,
					Reason: "mango config lines hold 255 characters; this bind's command is too long. " +
						"Put the command in a script and bind the script.",
				})
				continue
			}
			add(k.Keys, entry{b: outBind{mods: mods, key: key, cmd: cmd, verb: verb}, rank: 3})
			continue
		}
		if reason != "" {
			report = append(report, wm.Unhonored{Key: "bind.custom." + k.Keys, Reason: reason})
		} else if !keyOK {
			report = append(report, wm.Unhonored{Key: "bind.custom." + k.Keys, Reason: "mango cannot bind " + k.Keys + "."})
		}
	}

	out := make([]outBind, 0, len(seen))
	for _, k := range order {
		out = append(out, seen[k].b)
	}
	return out, report
}

// tagOfChord pulls the tag digit out of an expanded family chord: "SUPER + 3"
// -> "3", the tenth member "SUPER + 0" -> "0", a keypad chord "SUPER + KP_7"
// -> "7". A chord with no digit gets "1".
func tagOfChord(chord string) string {
	for _, tok := range strings.Split(chord, "+") {
		t := strings.TrimSpace(tok)
		if len(t) == 1 && t[0] >= '0' && t[0] <= '9' {
			return t
		}
		if len(t) >= 3 && strings.HasPrefix(t, "KP_") {
			return t[3:]
		}
	}
	return "1"
}

// genBinds renders rebinds.conf and returns the binds it could not honour. The
// file is always written, empty included: the shipped entry sources it, and a
// complete validating tree is the apply contract.
func genBinds(s mangoStore) (string, []wm.Unhonored) {
	out, report := resolveBinds(s)

	var b strings.Builder
	b.WriteString("# Generated by Ryoku Settings (Super + ,). Edit binds in the GUI, not here.\n")
	b.WriteString("# One complete chord set: defaults, rebinds applied, unbinds removed,\n")
	b.WriteString("# custom binds appended. mango keeps the last of a duplicate chord, so\n")
	b.WriteString("# every chord here has exactly one winner.\n\n")
	for _, o := range out {
		b.WriteString(o.verb)
		b.WriteString("=")
		b.WriteString(o.mods)
		b.WriteString(",")
		b.WriteString(o.key)
		if o.cmd != "" {
			b.WriteString(",")
			b.WriteString(o.cmd)
		}
		b.WriteString("\n")
	}
	return b.String(), report
}

// bindRows is the full effective legend the binds verb prints: every catalogue
// row in catalogue order (its chord resolved against the user's rebinds, its
// copy overridden where mango's mechanic differs, and marked unhonored where
// mango cannot perform it), then the user's custom binds.
func bindRows(s mangoStore) []wm.BindRow {
	defs := defaultBinds()
	var rows []wm.BindRow
	for _, cb := range wm.ShippedBinds() {
		mb := defs[cb.ID]
		defChord := cb.Chord
		if cb.Family {
			if rc, ok := wm.FamilyRebind(defChord, s.KeybindRebinds); ok {
				defChord = rc
			}
		} else if v, ok := effectiveChord(defChord, s.KeybindRebinds); ok {
			defChord = v
		}
		label, hint := cb.Label, cb.Hint
		if mb.label != "" {
			label = mb.label
		}
		if mb.hint != "" {
			hint = mb.hint
		}
		row := wm.BindRow{
			ID:         cb.ID,
			Category:   cb.Category,
			Label:      label,
			Hint:       hint,
			Keys:       wm.DisplayKeys(defChord),
			Default:    cb.Chord,
			Chord:      defChord,
			Kind:       cb.Kind,
			Rebindable: rebindable(cb),
			Locked:     cb.Locked,
		}
		if mb.reason != "" {
			row.Unhonored = mb.reason
		}
		rows = append(rows, row)
	}
	for _, k := range s.Keybinds {
		if strings.TrimSpace(k.Keys) == "" {
			continue
		}
		_, reason := customCommand(k)
		row := wm.BindRow{
			ID:       "custom." + k.Keys,
			Category: "Custom",
			Label:    customLabel(k),
			Keys:     wm.DisplayKeys(k.Keys),
			Chord:    k.Keys,
			Kind:     wm.BindCustom,
		}
		if reason != "" {
			row.Unhonored = reason
		}
		rows = append(rows, row)
	}
	return rows
}

// rebindable reports whether the Hub may let a user record a new chord over
// this bind. Media and hardware chords ride dedicated keys and stay fixed.
func rebindable(cb wm.CatalogBind) bool {
	return !cb.Locked
}

// runBinds prints the effective bind legend as a JSON array of wm.BindRow,
// read through the store so the chords reflect what the session actually emits.
func runBinds(args []string) error {
	path := storePath()
	if len(args) > 0 && strings.TrimSpace(args[0]) != "" {
		path = args[0]
	}
	s := loadStore(path)
	rows := bindRows(s)
	if rows == nil {
		rows = []wm.BindRow{}
	}
	enc := json.NewEncoder(stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(rows)
}

// effectiveChord resolves a default's emitted chord: the user's rebind when
// set, otherwise the shipped chord. The bool reports whether a rebind applied.
func effectiveChord(def string, rebinds map[string]string) (string, bool) {
	if rebinds == nil {
		return def, false
	}
	if v, ok := rebinds[def]; ok && strings.TrimSpace(v) != "" {
		return v, true
	}
	return def, false
}

// customCommand maps a store keybind action onto its mango command tail. exec
// runs the value through spawn_shell; the window actions take the dispatcher.
// An unknown action (a submap or a plugin toggle from another compositor)
// yields a reason so the bind is reported, not dropped.
func customCommand(k Keybind) (cmd, reason string) {
	switch k.Action {
	case "exec":
		if strings.TrimSpace(k.Value) == "" {
			return "", "an exec bind needs a command."
		}
		if strings.Contains(k.Value, ",") {
			return "", "mango cannot run a command containing a comma."
		}
		return "spawn_shell," + k.Value, ""
	case "close":
		return "killclient", ""
	case "fullscreen":
		return "togglefullscreen", ""
	case "float":
		return "togglefloating", ""
	case "workspace":
		t, err := customTag(k.Value)
		if err != nil {
			return "", err.Error()
		}
		return "view," + t, ""
	case "moveToWorkspace":
		t, err := customTag(k.Value)
		if err != nil {
			return "", err.Error()
		}
		return "tag," + t, ""
	case "scratchpad":
		return "toggle_scratchpad", ""
	case "overview":
		return "toggleoverview", ""
	default:
		return "", "mango has no action for a " + k.Action + " bind."
	}
}

// customTag validates a custom bind's workspace value: mango's numbered tags
// are 1 through tag_num (9 as shipped); anything else is refused with the
// reason a switch preview shows.
func customTag(v string) (string, error) {
	n, err := strconv.Atoi(strings.TrimSpace(v))
	if err != nil || n < 1 || n > 9 {
		return "", fmt.Errorf("a workspace bind names a tag number 1-9 on mango")
	}
	return strconv.Itoa(n), nil
}

// customLabel is the human text the legend shows for a store keybind, derived
// from its action so the row reads like the shipped legend.
func customLabel(k Keybind) string {
	switch k.Action {
	case "exec":
		if k.Value == "" {
			return "Custom bind"
		}
		name := k.Value
		if i := strings.IndexByte(name, ' '); i > 0 {
			name = name[:i]
		}
		return "Run " + name
	case "close":
		return "Close window"
	case "fullscreen":
		return "Fullscreen"
	case "float":
		return "Float or tile"
	case "workspace":
		return "Workspace " + k.Value
	case "moveToWorkspace":
		return "Send to workspace " + k.Value
	case "scratchpad":
		return "Scratchpad"
	case "overview":
		return "Overview"
	default:
		return "Custom bind"
	}
}

// toMangoParts rewrites a Hub display chord ("SUPER + SHIFT + Left") as mango's
// modifier and key fields. ok is false for a chord with no key token.
func toMangoParts(chord string) (mods, key string, ok bool) {
	tokens := strings.Split(chord, "+")
	var modsList []string
	for _, raw := range tokens {
		t := strings.TrimSpace(raw)
		if t == "" {
			continue
		}
		if m, isMod := mangoMod(t); isMod {
			modsList = append(modsList, m)
			continue
		}
		key = t
	}
	if key == "" {
		return "", "", false
	}
	if len(modsList) == 0 {
		modsList = []string{"NONE"}
	}
	return strings.Join(modsList, "+"), key, true
}

// toMangoChord turns a catalogue chord into the emitted verb and fields. Wheel
// chords become axisbind, pointer buttons become mousebind, and the locked
// media/hardware rows become bindl (mango's `l` flag). ok is false for a key
// name mango cannot bind.
func toMangoChord(chord string, kind string) (verb, mods, key string, ok bool) {
	mods, rawKey, ok := toMangoParts(chord)
	if !ok {
		return "", "", "", false
	}
	verb = kind
	if verb == "" {
		verb = "bind"
	}
	switch rawKey {
	case "mouse_up":
		return "axisbind", mods, "UP", true
	case "mouse_down":
		return "axisbind", mods, "DOWN", true
	case "mouse:272":
		return "mousebind", mods, "btn_left", true
	case "mouse:273":
		return "mousebind", mods, "btn_right", true
	case "mouse:274":
		return "mousebind", mods, "btn_middle", true
	}
	k, ok := mangoKey(rawKey)
	if !ok {
		return "", "", "", false
	}
	return verb, mods, k, true
}

// mangoMod maps a display modifier token onto mango's spelling.
func mangoMod(tok string) (string, bool) {
	switch strings.ToUpper(tok) {
	case "SUPER", "WIN", "MOD4":
		return "SUPER", true
	case "CTRL", "CONTROL":
		return "CTRL", true
	case "ALT":
		return "ALT", true
	case "SHIFT":
		return "SHIFT", true
	case "NONE":
		return "NONE", true
	}
	return "", false
}

// mangoKey normalises a key token to its keysym name. A lone letter takes its
// lowercase keysym (mango upper-cases into the layout internally); "Space"
// takes the spelling the shipped mango config uses; everything else passes
// through: mango resolves names against the configured layouts with a us
// fallback, and the catalogue's keysym faces (Prior, Home, KP_1,
// XF86AudioRaiseVolume, comma, grave, bracketleft) are exactly those names.
// The pseudo tokens left over from the wheel/button rewrite have no key name
// and fail.
func mangoKey(tok string) (string, bool) {
	if len(tok) == 1 && tok[0] >= 'A' && tok[0] <= 'Z' {
		return strings.ToLower(tok), true
	}
	if tok == "Space" {
		return "space", true
	}
	if strings.HasPrefix(tok, "mouse:") || strings.HasPrefix(tok, "mouse_") {
		return "", false
	}
	return tok, true
}
