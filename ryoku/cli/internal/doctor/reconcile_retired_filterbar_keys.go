package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// The Ryogami picker's skwd filter bar is replaced by one masthead pinned to the top
// of the picker, so its style, orientation and offset keys have no schema entry any
// more. Left in ryogami.json they are foreign data the daemon carries forever; this
// strips them. Surgical and idempotent: a store already free of them is untouched.
func reconcileRetiredFilterBarKeys(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "ryogami.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no ryogami.json yet (seeded on first picker run)"))
	}
	migrated, changed, err := stripRetiredFilterBarKeys(raw)
	if err != nil {
		return warnRes(i18n.T("ryogami.json does not parse (%v); Ryogami falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("ryogami.json carries no retired filter bar keys"))
	}
	if checkOnly {
		return wouldRes(i18n.T("ryogami.json still carries the retired filter bar style keys")).
			withFix(i18n.T("ryoku doctor strips them in place"))
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("stripped the retired filter bar style keys from ryogami.json"))
}

var retiredFilterBarKeys = []string{"visualStyle", "orientation", "offsetX", "offsetY"}

// stripRetiredFilterBarKeys drops the retired keys from a Ryogami store's filterBar
// object, keeping every other key as its own raw bytes. An absent filterBar, or one
// already free of them, is a no-op; a filterBar left empty is dropped; a malformed
// filterBar errors rather than being rewritten.
func stripRetiredFilterBarKeys(raw []byte) (out []byte, changed bool, err error) {
	var top map[string]json.RawMessage
	if err = json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	barRaw, ok := top["filterBar"]
	if !ok {
		return nil, false, nil
	}
	var bar map[string]json.RawMessage
	if err = json.Unmarshal(barRaw, &bar); err != nil {
		return nil, false, err
	}
	for _, key := range retiredFilterBarKeys {
		if _, ok := bar[key]; ok {
			delete(bar, key)
			changed = true
		}
	}
	if !changed {
		return nil, false, nil
	}
	if len(bar) == 0 {
		delete(top, "filterBar")
	} else {
		repacked, err := json.Marshal(bar)
		if err != nil {
			return nil, false, err
		}
		top["filterBar"] = repacked
	}
	out, err = json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}
