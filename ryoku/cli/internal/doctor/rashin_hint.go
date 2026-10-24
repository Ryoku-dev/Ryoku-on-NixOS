package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"
)

// rashinOn reports whether Rashin, Ryoku's optional local agent OS, is switched
// on for this box: ~/.config/ryoku/rashin.json parses with "enabled": true and
// the ryoku-rashin binary resolves on PATH. Both are required, since the config
// gate is meaningless without the daemon that `ryoku-rashin fix doctor` drives.
// It decides whether doctor offers the "let Rashin fix these" line beside the
// existing --explain hint.
func rashinOn() bool {
	if !sys.Has("ryoku-rashin") {
		return false
	}
	b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "ryoku", "rashin.json"))
	if err != nil {
		return false
	}
	var c struct {
		Enabled bool `json:"enabled"`
	}
	return json.Unmarshal(b, &c) == nil && c.Enabled
}
