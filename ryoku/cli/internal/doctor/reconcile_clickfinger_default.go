package doctor

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

const clickfingerDefaultMigration = "desktop-clickfinger-default"

func clickfingerDefaultMarker() string {
	return filepath.Join(sys.StateDir(), "migrations", clickfingerDefaultMigration)
}

// reconcileClickfingerDefault moves the retired saved default once. The marker
// makes a later user-selected false value authoritative.
func reconcileClickfingerDefault(checkOnly bool) recResult {
	marker := clickfingerDefaultMarker()
	if sys.Exists(marker) {
		return okRes(i18n.T("clickfinger default already reconciled"))
	}

	store := filepath.Join(sys.ConfigHome(), "ryoku", "desktop.json")
	raw, err := os.ReadFile(store)
	if errors.Is(err, os.ErrNotExist) {
		if checkOnly {
			return okRes(i18n.T("no saved desktop input; clickfinger uses the current default"))
		}
		if err := markMigration(marker); err != nil {
			return failRes(i18n.T("could not record the clickfinger migration: %v"), err)
		}
		return okRes(i18n.T("no saved desktop input; clickfinger uses the current default"))
	}
	if err != nil {
		return warnRes(i18n.T("could not read %s for the clickfinger migration: %v"), store, err).
			withFix(i18n.T("fix the file permissions, then run `ryoku doctor`"))
	}

	migrated, changed, err := migrateClickfingerDefault(raw)
	if err != nil {
		return warnRes(i18n.T("desktop.json cannot be safely migrated (%v); it was left untouched"), err).
			withFix(i18n.T("repair desktop.input.clickfinger, then run `ryoku doctor`"))
	}
	if changed && checkOnly {
		return wouldRes(i18n.T("desktop input still uses the retired clickfinger default"))
	}
	if !changed {
		if checkOnly {
			return okRes(i18n.T("clickfinger is user-selected or already uses the current default"))
		}
		if err := markMigration(marker); err != nil {
			return failRes(i18n.T("could not record the clickfinger migration: %v"), err)
		}
		return okRes(i18n.T("clickfinger is user-selected or already uses the current default"))
	}

	if err := replaceClickfingerStore(store, migrated); err != nil {
		return failRes(i18n.T("could not migrate %s: %v"), store, err).
			withFix(i18n.T("fix the file permissions, then run `ryoku doctor`"))
	}
	if err := markMigration(marker); err != nil {
		return failRes(i18n.T("clickfinger was updated, but its migration marker could not be written: %v"), err).
			withFix(i18n.T("run `ryoku doctor` again"))
	}
	return fixedRes(i18n.T("enabled clickfinger for buttonless touchpads"))
}

// migrateClickfingerDefault changes only the shared neutral input leaf. Both
// providers consume desktop.input.clickfinger; neither keeps a private copy.
func migrateClickfingerDefault(raw []byte) ([]byte, bool, error) {
	var doc map[string]json.RawMessage
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, false, err
	}
	if doc == nil {
		return nil, false, errors.New(i18n.T("top level must be a JSON object"))
	}

	desktopRaw, ok := doc["desktop"]
	if !ok {
		return nil, false, nil
	}
	var desktop map[string]json.RawMessage
	if err := json.Unmarshal(desktopRaw, &desktop); err != nil || desktop == nil {
		return nil, false, errors.New(i18n.T("desktop must be an object"))
	}
	inputRaw, ok := desktop["input"]
	if !ok {
		return nil, false, nil
	}
	var input map[string]json.RawMessage
	if err := json.Unmarshal(inputRaw, &input); err != nil || input == nil {
		return nil, false, errors.New(i18n.T("desktop.input must be an object"))
	}
	clickfinger, ok := input["clickfinger"]
	if !ok {
		return nil, false, nil
	}
	switch string(bytes.TrimSpace(clickfinger)) {
	case "true":
		return nil, false, nil
	case "false":
		input["clickfinger"] = json.RawMessage("true")
	default:
		return nil, false, errors.New(i18n.T("desktop.input.clickfinger must be boolean"))
	}

	inputRaw, err := json.Marshal(input)
	if err != nil {
		return nil, false, err
	}
	desktop["input"] = inputRaw
	desktopRaw, err = json.Marshal(desktop)
	if err != nil {
		return nil, false, err
	}
	doc["desktop"] = desktopRaw
	out, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}

func replaceClickfingerStore(path string, data []byte) error {
	target := path
	linkInfo, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if linkInfo.Mode()&os.ModeSymlink != 0 {
		target, err = filepath.EvalSymlinks(path)
		if err != nil {
			return err
		}
	}

	info, err := os.Stat(target)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(target), ".desktop.json.ryoku-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)

	if err := tmp.Chmod(info.Mode().Perm()); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpPath, target)
}
