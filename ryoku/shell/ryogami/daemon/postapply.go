package main

import (
	"errors"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// The apply path treats it as skip-painting, not as a failure.
var errPickOnly = errors.New("ryogami: pick-only mode")

type postCommand struct {
	command string
	typ     string
}

func restoreLikeApply(reason string) bool {
	switch reason {
	case "restore", "reload", "live-reload", "init", "hotplug":
		return true
	}
	return false
}

func init() {
	guardApply(func(d *daemon, _ *applyRequest) error {
		if d.settingBool("pickOnlyMode") {
			return errPickOnly
		}
		return nil
	})

	// Restore-like reasons run from the onStart hook below, so nothing runs twice.
	afterApply(func(d *daemon, ev applyEvent) {
		if restoreLikeApply(ev.Reason) {
			return
		}
		d.runPostProcessing(ev, false)
	})

	onStart(func(d *daemon) {
		if !d.settingBool("postProcessOnRestore") {
			return
		}
		if ev, ok := d.restoredApplyEvent(); ok {
			d.runPostProcessing(ev, true)
		}
	})
}

func (d *daemon) runPostProcessing(ev applyEvent, restoring bool) {
	cmds := d.postProcessCommands()
	if len(cmds) == 0 {
		return
	}
	thumb := ""
	if e, ok := d.store.get(ev.Key); ok {
		thumb = e.Thumb
	}
	for _, c := range cmds {
		if c.typ != "all" && c.typ != ev.Type {
			continue
		}
		resolved := expandPostPlaceholders(c.command, ev.Type, ev.Name, ev.Path, thumb)
		runDetachedShell(resolved)
	}
}

func (d *daemon) postProcessCommands() []postCommand {
	return parsePostCommands(d.settingList("postProcessing"))
}

func parsePostCommands(items []interface{}) []postCommand {
	var out []postCommand
	for _, item := range items {
		switch v := item.(type) {
		case string:
			if strings.TrimSpace(v) != "" {
				out = append(out, postCommand{command: v, typ: "all"})
			}
		case map[string]interface{}:
			cmd, _ := v["command"].(string)
			if strings.TrimSpace(cmd) == "" {
				continue
			}
			typ, _ := v["type"].(string)
			if typ == "" {
				typ = "all"
			}
			out = append(out, postCommand{command: cmd, typ: typ})
		}
	}
	return out
}

// Each value is shell-quoted so a crafted filename cannot break out of the command.
func expandPostPlaceholders(template, wpType, name, path, thumb string) string {
	return strings.NewReplacer(
		"%type%", shellQuote(wpType),
		"%name%", shellQuote(name),
		"%path%", shellQuote(path),
		"%thumb%", shellQuote(thumb),
	).Replace(template)
}

func shellQuote(text string) string {
	return "'" + strings.ReplaceAll(text, "'", `'\''`) + "'"
}

// Fully detached so a long-running setter neither blocks the reply nor dies with the daemon.
func runDetachedShell(command string) {
	wrapped := "nohup setsid sh -c " + shellQuote(command) + " </dev/null >/dev/null 2>&1 &"
	cmd := exec.Command("sh", "-c", wrapped)
	if err := cmd.Start(); err != nil {
		return
	}
	go func() { _ = cmd.Wait() }()
}

func (d *daemon) restoredApplyEvent() (applyEvent, bool) {
	state := map[string]map[string]interface{}{}
	loadJSON(filepath.Join(d.config().cacheDir(), "outputs.json"), &state)
	entry := state["*"]
	if entry == nil {
		keys := make([]string, 0, len(state))
		for k := range state {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		if len(keys) > 0 {
			entry = state[keys[0]]
		}
	}
	if entry == nil {
		return applyEvent{}, false
	}
	path, _ := entry["path"].(string)
	if path == "" {
		return applyEvent{}, false
	}
	wpType, _ := entry["type"].(string)
	name := filepath.Base(path)
	key := strings.TrimSuffix(name, filepath.Ext(name))
	return applyEvent{
		applyRequest: applyRequest{Type: wpType, Path: path, Reason: "restore"},
		Name:         name,
		Key:          key,
	}, true
}
