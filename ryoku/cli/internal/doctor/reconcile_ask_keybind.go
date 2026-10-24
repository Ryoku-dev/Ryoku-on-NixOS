package doctor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

func reconcileAskKeybind(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	migrated, changed, err := migrateAskKeybind(raw)
	if err != nil {
		return warnRes(i18n.T("shell.json does not parse (%v); the shell falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("shell.json carries no retired panel keybind"))
	}
	if checkOnly {
		return wouldRes(i18n.T("shell.json still carries the retired panel keybind")).
			withFix(i18n.T("ryoku doctor removes it in place"))
	}

	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("removed the retired panel keybind from shell.json"))
}

// migrateAskKeybind removes the orphaned Super+S rebind left by the retired
// surface. Every sibling key remains a raw JSON value, and a clean store is a
// no-op.
func migrateAskKeybind(raw []byte) ([]byte, bool, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	if top == nil {
		return nil, false, fmt.Errorf("top-level shell config is null")
	}

	desktopRaw, present := top["desktop"]
	if !present {
		return nil, false, nil
	}
	var desktop map[string]json.RawMessage
	if err := json.Unmarshal(desktopRaw, &desktop); err != nil {
		return nil, false, fmt.Errorf("desktop does not parse: %w", err)
	}
	if desktop == nil {
		return nil, false, fmt.Errorf("desktop is null")
	}

	rebindsRaw, present := desktop["keybindRebinds"]
	if !present {
		return nil, false, nil
	}
	var rebinds map[string]json.RawMessage
	if err := json.Unmarshal(rebindsRaw, &rebinds); err != nil {
		return nil, false, fmt.Errorf("desktop.keybindRebinds does not parse: %w", err)
	}
	if rebinds == nil {
		return nil, false, fmt.Errorf("desktop.keybindRebinds is null")
	}
	if _, present := rebinds["SUPER + S"]; !present {
		return nil, false, nil
	}

	delete(rebinds, "SUPER + S")
	nextRebinds, err := json.Marshal(rebinds)
	if err != nil {
		return nil, false, err
	}
	desktop["keybindRebinds"] = nextRebinds
	nextDesktop, err := json.Marshal(desktop)
	if err != nil {
		return nil, false, err
	}
	top["desktop"] = nextDesktop
	out, err := json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}
