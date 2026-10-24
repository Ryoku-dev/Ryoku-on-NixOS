package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// Ryogami paints stills and video itself, so two generations of renderer keys are
// retired: the awww engine (paper.awww.*, paper.engine == "awww") and the
// skwd-paper image/video engine (paper.engine, paper.videoEngine,
// paper.wallpaperLayer, paper.videoMultiProcess). skwd-paper stays only as the
// Wallpaper Engine scene renderer, which needs no engine choice. A stored value
// the schema no longer offers makes the picker show a dead selection, so this
// strips them. Surgical and idempotent: a store already free of them is untouched.
func reconcileRetiredPaperKeys(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "ryogami.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no ryogami.json yet (seeded on first picker run)"))
	}
	migrated, changed, err := stripRetiredPaperKeys(raw)
	if err != nil {
		return warnRes(i18n.T("ryogami.json does not parse (%v); Ryogami falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("ryogami.json carries no retired wallpaper-engine keys"))
	}
	if checkOnly {
		return wouldRes(i18n.T("ryogami.json still carries retired wallpaper-engine keys")).
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
	return fixedRes(i18n.T("stripped the retired wallpaper-engine keys from ryogami.json"))
}

// retiredPaperKeys have no schema entry any more; a stored value would show as a
// dead selection in the picker.
var retiredPaperKeys = []string{"videoEngine", "wallpaperLayer", "videoMultiProcess"}

// stripRetiredPaperKeys drops the paper.awww object, the retired engine choice
// keys, and a paper.engine left on the retired "awww" from a Ryogami store,
// keeping every other key as its own raw bytes. An absent paper object, or one
// already free of them, is a no-op; a malformed paper object errors rather than
// being rewritten.
func stripRetiredPaperKeys(raw []byte) (out []byte, changed bool, err error) {
	var top map[string]json.RawMessage
	if err = json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	paperRaw, ok := top["paper"]
	if !ok {
		return nil, false, nil
	}
	var paper map[string]json.RawMessage
	if err = json.Unmarshal(paperRaw, &paper); err != nil {
		return nil, false, err
	}
	if _, ok := paper["awww"]; ok {
		delete(paper, "awww")
		changed = true
	}
	for _, key := range retiredPaperKeys {
		if _, ok := paper[key]; ok {
			delete(paper, key)
			changed = true
		}
	}
	// The engine choice itself is gone: Ryoku paints, so any stored value is dead.
	if _, ok := paper["engine"]; ok {
		delete(paper, "engine")
		changed = true
	}
	if !changed {
		return nil, false, nil
	}
	if len(paper) == 0 {
		delete(top, "paper")
	} else {
		repacked, err := json.Marshal(paper)
		if err != nil {
			return nil, false, err
		}
		top["paper"] = repacked
	}
	out, err = json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}
