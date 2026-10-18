package doctor

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

var vesktopPaletteInstaller = "/usr/share/ryoku/palette-bridge/install-integrations.sh"

// Only the exact old bridge-owned registration is migrated. Disabled QuickCSS
// and edited registrations express user choices, even if ownership remains.
func legacyVesktopPalette(config, state string) bool {
	template := filepath.Join(config, "ryoku/user_edits/matugen/templates/vesktop-colors.css")
	owned, err := os.ReadFile(filepath.Join(state, "ryoku/palette-bridge/owned-files.tsv"))
	if err != nil {
		return false
	}
	found := false
	for _, line := range strings.Split(string(owned), "\n") {
		if line == "vesktop\t"+template {
			found = true
		}
	}
	if !found {
		return false
	}
	raw, err := os.ReadFile(filepath.Join(config, "vesktop/settings/settings.json"))
	var settings struct {
		UseQuickCSS bool `json:"useQuickCss"`
	}
	if err != nil || json.Unmarshal(raw, &settings) != nil || !settings.UseQuickCSS {
		return false
	}
	raw, err = os.ReadFile(filepath.Join(config, "ryoku/user_edits/matugen/apps.toml"))
	if err != nil {
		return false
	}
	var section []string
	active := false
	for _, line := range strings.Split(string(raw), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") {
			if active {
				break
			}
			active = line == "[templates.vesktop]"
			continue
		}
		if active && line != "" {
			section = append(section, line)
		}
	}
	if len(section) != 2 {
		return false
	}
	input := filepath.Join(config, "matugen/templates/vesktop-colors.css")
	output := filepath.Join(config, "vesktop/settings/quickCss.css")
	return (section[0] == `input_path = "`+input+`"` && section[1] == `output_path = "`+output+`"`) ||
		(config == filepath.Join(homeDir(), ".config") && section[0] == `input_path = "~/.config/matugen/templates/vesktop-colors.css"` && section[1] == `output_path = "~/.config/vesktop/settings/quickCss.css"`)
}

func reconcileVesktopPalette(checkOnly bool) recResult {
	if !legacyVesktopPalette(sys.ConfigHome(), sys.Xdg("XDG_STATE_HOME", ".local/state")) {
		return okRes(i18n.T("no active legacy Vesktop palette registration"))
	}
	if _, err := os.Stat(vesktopPaletteInstaller); err != nil {
		return warnRes(i18n.T("Vesktop palette setup helper is unavailable; update ryoku-palette-bridge"))
	}
	capabilities, err := exec.Command("bash", vesktopPaletteInstaller, "--capabilities").Output()
	if err != nil || strings.TrimSpace(string(capabilities)) != "vesktop-preserve-quickcss-v1" {
		return warnRes(i18n.T("Vesktop palette setup is outdated; update ryoku-palette-bridge before repairing its registration"))
	}
	if checkOnly {
		return wouldRes(i18n.T("Vesktop palette rendering replaces custom QuickCSS")).withFix("ryoku doctor")
	}
	if out, err := exec.Command("bash", vesktopPaletteInstaller, "--vesktop").CombinedOutput(); err != nil {
		return failRes(i18n.T("could not migrate Vesktop palette registration: %v (%s)"), err, strings.TrimSpace(string(out)))
	}
	if !preservingVesktopPalette(sys.ConfigHome(), sys.Xdg("XDG_STATE_HOME", ".local/state")) {
		return failRes(i18n.T("Vesktop palette setup still writes directly to QuickCSS; update ryoku-palette-bridge and rerun ryoku doctor"))
	}
	return fixedRes(i18n.T("Vesktop palette updates now preserve custom QuickCSS and imports"))
}

func preservingVesktopPalette(config, state string) bool {
	root := filepath.Join(state, "ryoku/palette-bridge/vesktop")
	installed, err := os.ReadFile(filepath.Join(root, "quickcss.sh"))
	if err != nil || len(installed) == 0 {
		return false
	}
	packaged, err := os.ReadFile(filepath.Join(filepath.Dir(vesktopPaletteInstaller), "vesktop/quickcss.sh"))
	if err != nil || !bytes.Equal(installed, packaged) {
		return false
	}
	raw, err := os.ReadFile(filepath.Join(config, "ryoku/user_edits/matugen/apps.toml"))
	if err != nil {
		return false
	}
	quote := func(s string) string { return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'" }
	hook := "bash " + quote(filepath.Join(root, "quickcss.sh")) + " " + quote(filepath.Join(config, "vesktop/settings/quickCss.css")) + " " + quote(filepath.Join(root, "palette.css"))
	encodedOutput, _ := json.Marshal(filepath.Join(root, "palette.css"))
	active, output, post := false, false, false
	for _, line := range strings.Split(string(raw), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") {
			if active {
				break
			}
			active = line == "[templates.vesktop]"
			continue
		}
		if active {
			output = output || line == "output_path = "+string(encodedOutput)
			if strings.HasPrefix(line, "post_hook = ") {
				var decoded string
				if json.Unmarshal([]byte(strings.TrimPrefix(line, "post_hook = ")), &decoded) == nil {
					post = decoded == hook
				}
			}
		}
	}
	return output && post
}
