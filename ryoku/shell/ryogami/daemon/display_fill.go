package main

import "strings"

// The override applies at publish time and is never stored in the per-output state.

var fitOverrides func() map[string]string

func init() {
	onStart(func(d *daemon) {
		fitOverrides = d.fillModeOverrides
		if len(d.fillModeOverrides()) > 0 {
			d.surface.republish()
		}
	})
	watchSetting("display.fillModes", func(d *daemon, _ string, _ interface{}) { d.surface.republish() })
}

func (d *daemon) fillModeOverrides() map[string]string {
	m := d.settingMap("display.fillModes")
	if len(m) == 0 {
		return nil
	}
	out := map[string]string{}
	for name, v := range m {
		mode, ok := v.(string)
		if !ok {
			continue
		}
		mode = strings.TrimSpace(mode)
		// The sentinel means "inherit the global fit": no override.
		if mode == "" || mode == "(inherits display.fillMode)" {
			continue
		}
		fit := modeToContentFit(mode)
		if fit == "" {
			continue
		}
		out[name] = fit
	}
	if len(out) == 0 {
		return nil
	}
	return out
}
