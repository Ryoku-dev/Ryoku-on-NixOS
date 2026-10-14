package doctor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// Shima's warning notifications moved to the shell-wide battery-alert service.
// Its old thresholds no longer control anything and must not be seeded back into
// the family store after the corresponding settings rows are removed.
func reconcileIrisBatteryThresholds(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	if err != nil {
		return failRes(i18n.T("could not read %s: %v"), path, err)
	}
	migrated, changed, err := stripIrisBatteryThresholds(raw)
	if err != nil {
		return failRes(i18n.T("shell.json could not be migrated: %v"), err)
	}
	if !changed {
		return okRes(i18n.T("shell.json carries no retired Shima battery warning thresholds"))
	}
	if checkOnly {
		return failRes(i18n.T("shell.json still carries retired Shima battery warning thresholds"))
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("removed retired Shima battery warning thresholds from shell.json"))
}

func stripIrisBatteryThresholds(raw []byte) ([]byte, bool, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	if top == nil {
		return nil, false, fmt.Errorf("top-level shell config is null")
	}
	inirRaw, present := top["inir"]
	if !present {
		return nil, false, nil
	}
	var inir map[string]json.RawMessage
	if err := json.Unmarshal(inirRaw, &inir); err != nil {
		return nil, false, fmt.Errorf("inir: %w", err)
	}
	batteryRaw, present := inir["battery"]
	if !present {
		return nil, false, nil
	}
	var battery map[string]json.RawMessage
	if err := json.Unmarshal(batteryRaw, &battery); err != nil {
		return nil, false, fmt.Errorf("inir.battery: %w", err)
	}
	_, low := battery["low"]
	_, critical := battery["critical"]
	if !low && !critical {
		return nil, false, nil
	}
	delete(battery, "low")
	delete(battery, "critical")

	var err error
	if inir["battery"], err = json.Marshal(battery); err != nil {
		return nil, false, err
	}
	if top["inir"], err = json.Marshal(inir); err != nil {
		return nil, false, err
	}
	out, err := json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}
