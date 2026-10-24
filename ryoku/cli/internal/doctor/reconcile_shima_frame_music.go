package doctor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// Shima's "Music on the edges" used to choose between the Organic Edge wave
// and the frame through inir.iris.surround.music, but Ryoku hosts no Organic
// Edge widget, so the stored "widget" choice animated nothing. The switch now
// moves the frame on its own and the key is retired. Surgical and idempotent:
// a store without the key is left alone.
func reconcileShimaFrameMusic(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	migrated, changed, err := stripShimaFrameMusicKey(raw)
	if err != nil {
		return failRes(i18n.T("shell.json could not be migrated: %v"), err)
	}
	if !changed {
		return okRes(i18n.T("shell.json carries no retired Shima frame music key"))
	}
	if checkOnly {
		return failRes(i18n.T("shell.json still carries the retired Shima frame music key"))
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("removed the retired Shima frame music key from shell.json"))
}

// stripShimaFrameMusicKey drops inir.iris.surround.music, keeping every other
// key as its own raw bytes. A store without the inir, iris or surround objects
// is a no-op; a malformed one along that path errors rather than being rewritten.
func stripShimaFrameMusicKey(raw []byte) ([]byte, bool, error) {
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
	irisRaw, present := inir["iris"]
	if !present {
		return nil, false, nil
	}
	var iris map[string]json.RawMessage
	if err := json.Unmarshal(irisRaw, &iris); err != nil {
		return nil, false, fmt.Errorf("inir.iris: %w", err)
	}
	surroundRaw, present := iris["surround"]
	if !present {
		return nil, false, nil
	}
	var surround map[string]json.RawMessage
	if err := json.Unmarshal(surroundRaw, &surround); err != nil {
		return nil, false, fmt.Errorf("inir.iris.surround: %w", err)
	}
	if _, present := surround["music"]; !present {
		return nil, false, nil
	}
	delete(surround, "music")

	var err error
	if iris["surround"], err = json.Marshal(surround); err != nil {
		return nil, false, err
	}
	if inir["iris"], err = json.Marshal(iris); err != nil {
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
