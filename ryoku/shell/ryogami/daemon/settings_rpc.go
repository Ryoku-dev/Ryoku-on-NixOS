package main

import (
	"fmt"
	"sort"

	wm "ryoku-wm"
)

func (d *daemon) dispatchSettings(req *request, p map[string]interface{}) (response, bool) {
	switch req.Method {
	case "settings.schema":
		return d.settingsSchema(req), true
	case "settings.get":
		return ok(req.ID, map[string]interface{}{"values": d.collectValues(strsParam(p, "keys"))}), true
	case "settings.set":
		return d.settingsSet(req, p), true
	case "settings.reset":
		return d.settingsReset(req, p), true
	case "settings.action":
		return d.settingsAction(req, p), true
	}
	return response{}, false
}

func (d *daemon) settingsSchema(req *request) response {
	caps, _ := wmClient.Caps()
	capMap := make(map[string]bool, len(wm.All()))
	for _, c := range wm.All() {
		capMap[string(c)] = caps.Has(c)
	}
	return ok(req.ID, map[string]interface{}{
		"revision":     settingsRevision,
		"keys":         settingsSchema,
		"availability": d.availabilityMap(),
		"caps":         capMap,
	})
}

func (d *daemon) settingsSet(req *request, p map[string]interface{}) response {
	raw, hasValues := p["values"].(map[string]interface{})
	if !hasValues {
		return errResp(req.ID, 1, "missing 'values' parameter")
	}
	keys := sortedKeys(raw)
	// Validate the whole batch first so a bad value never leaves a half-applied set.
	for _, k := range keys {
		if err := validateSetting(k, raw[k]); err != nil {
			return errResp(req.ID, 5, err.Error())
		}
	}
	for _, k := range keys {
		if err := d.persistSetting(k, raw[k]); err != nil {
			return errResp(req.ID, 4, fmt.Sprintf("%s: %v", k, err))
		}
	}
	d.broadcast("ryogami.settings.changed", map[string]interface{}{"values": raw})
	for _, k := range keys {
		d.notifySetting(k, raw[k])
	}
	return ok(req.ID, map[string]interface{}{"ok": true})
}

func (d *daemon) settingsReset(req *request, p map[string]interface{}) response {
	keys := strsParam(p, "keys")
	if len(keys) == 0 {
		return errResp(req.ID, 1, "missing 'keys' parameter")
	}
	defaults := map[string]interface{}{}
	for _, k := range keys {
		if err := d.resetSetting(k); err != nil {
			return errResp(req.ID, 4, fmt.Sprintf("%s: %v", k, err))
		}
		if spec, ok := specFor(k); ok {
			defaults[k] = spec.Default
		} else {
			defaults[k] = nil
		}
	}
	d.broadcast("ryogami.settings.changed", map[string]interface{}{"values": defaults})
	for k, v := range defaults {
		d.notifySetting(k, v)
	}
	return ok(req.ID, map[string]interface{}{"ok": true})
}

func (d *daemon) settingsAction(req *request, p map[string]interface{}) response {
	id := strParam(p, "id", "")
	if id == "" {
		return errResp(req.ID, 1, "missing 'id' parameter")
	}
	args, _ := p["args"].(map[string]interface{})
	res, err := d.runAction(id, args)
	if err != nil {
		return errResp(req.ID, 4, err.Error())
	}
	return ok(req.ID, map[string]interface{}{"result": res})
}

// A key with no explicit value is omitted so the client falls back to the schema default.
func (d *daemon) collectValues(keys []string) map[string]interface{} {
	tree := currentRyogamiTree()
	shell := loadShellTree()
	hub := loadHubMap()
	out := map[string]interface{}{}
	if len(keys) > 0 {
		for _, k := range keys {
			if v, ok := d.explicitValue(k, tree, shell, hub); ok {
				out[k] = v
			}
		}
		return out
	}
	for i := range settingsSchema {
		k := settingsSchema[i].Key
		if v, ok := d.explicitValue(k, tree, shell, hub); ok {
			out[k] = v
		}
	}
	for k, v := range flattenSettings(tree) {
		// Only literal schema keys were covered above; per-output keys come from the tree.
		if _, isSchema := schemaIndex[k]; !isSchema {
			out[k] = v
		}
	}
	return out
}

// A shell or Hub value equal to the schema default reports as absent, like an unset key.
func (d *daemon) explicitValue(key string, tree, shell, hub map[string]interface{}) (interface{}, bool) {
	spec, ok := specFor(key)
	if !ok {
		return lookupDotted(tree, key)
	}
	switch spec.Store {
	case "shell":
		v, ok := d.shellExplicit(spec, tree, shell)
		if !ok || sameSetting(v, spec.Default) {
			return nil, false
		}
		return v, true
	case "hub":
		v, ok := hub[hubFieldByKey[spec.Key]]
		if !ok || sameSetting(v, spec.Default) {
			return nil, false
		}
		return v, true
	default:
		return lookupDotted(tree, key)
	}
}

func (d *daemon) shellExplicit(spec *settingSpec, tree, shell map[string]interface{}) (interface{}, bool) {
	if spec.Key == "display.fillMode" {
		if v, ok := lookupDotted(tree, "display.fillMode"); ok {
			return v, true
		}
		if v, ok := lookupDotted(shell, "wallpaper.content_fit"); ok {
			if s, ok := v.(string); ok {
				return contentFitToMode(s), true
			}
		}
		return nil, false
	}
	return lookupDotted(shell, shellKeyOf(spec))
}

// Overlaid with writes the debounced flush has not persisted, so a read after a write is consistent.
func currentRyogamiTree() map[string]interface{} {
	tree := loadRyogamiTree()
	if tree == nil {
		tree = map[string]interface{}{}
	}
	settingsMu.Lock()
	for k, v := range settingsPending {
		if isTombstone(v) {
			deleteDotted(tree, k)
		} else {
			setDotted(tree, k, v)
		}
	}
	settingsMu.Unlock()
	return tree
}

func sortedKeys(m map[string]interface{}) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
