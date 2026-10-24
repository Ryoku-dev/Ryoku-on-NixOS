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

func legacyVesktopPalette(config, state string) bool {
	template := filepath.Join(config, "ryoku/user_edits/matugen/templates/vesktop-colors.css")
	owned, err := os.ReadFile(filepath.Join(state, "ryoku/palette-bridge/owned-files.tsv"))
	if err != nil || !bytes.Contains(owned, []byte("vesktop\t"+template+"\n")) {
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
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.TrimSpace(line) == "[templates.vesktop]" {
			return true
		}
	}
	return false
}

func reconcileVesktopPalette(checkOnly bool) recResult {
	if !legacyVesktopPalette(sys.ConfigHome(), sys.Xdg("XDG_STATE_HOME", ".local/state")) {
		return okRes(i18n.T("no legacy Vesktop palette registration"))
	}
	if _, err := os.Stat(vesktopPaletteInstaller); err != nil {
		return warnRes(i18n.T("Vesktop palette setup helper is unavailable; update ryoku-palette-bridge"))
	}
	capabilities, err := exec.Command("bash", vesktopPaletteInstaller, "--capabilities").Output()
	if err != nil || strings.TrimSpace(string(capabilities)) != "palette-bridge-matugen-v2" {
		return warnRes(i18n.T("Vesktop palette setup is outdated; update ryoku-palette-bridge before repairing its registration"))
	}
	if checkOnly {
		return wouldRes(i18n.T("Vesktop palette integration forks the shipped Matugen app roster")).withFix("ryoku doctor")
	}
	if out, err := exec.Command("bash", vesktopPaletteInstaller, "--vesktop").CombinedOutput(); err != nil {
		return failRes(i18n.T("could not migrate Vesktop palette registration: %v (%s)"), err, strings.TrimSpace(string(out)))
	}
	if !preservingVesktopPalette(sys.ConfigHome(), sys.Xdg("XDG_DATA_HOME", ".local/share"), sys.Xdg("XDG_STATE_HOME", ".local/state")) {
		return failRes(i18n.T("Vesktop palette setup did not move to the supplemental Matugen config; update ryoku-palette-bridge and rerun ryoku doctor"))
	}
	return fixedRes(i18n.T("moved Vesktop palette rendering out of the shipped Matugen app roster"))
}

func preservingVesktopPalette(config, data, state string) bool {
	root := filepath.Join(state, "ryoku/palette-bridge/vesktop")
	installed, err := os.ReadFile(filepath.Join(root, "quickcss.sh"))
	if err != nil || len(installed) == 0 {
		return false
	}
	packagedRoot := filepath.Dir(vesktopPaletteInstaller)
	packaged, err := os.ReadFile(filepath.Join(packagedRoot, "vesktop/quickcss.sh"))
	if err != nil || !bytes.Equal(installed, packaged) {
		return false
	}
	template, err := os.ReadFile(filepath.Join(data, "ryoku/palette-bridge/templates/vesktop-colors.css"))
	packagedTemplate, packagedErr := os.ReadFile(filepath.Join(packagedRoot, "templates/vesktop-colors.css"))
	if err != nil || packagedErr != nil || !bytes.Equal(template, packagedTemplate) {
		return false
	}
	raw, err := os.ReadFile(filepath.Join(config, "ryoku/palette-bridge/matugen.toml"))
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
