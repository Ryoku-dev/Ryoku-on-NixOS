package doctor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestVesktopPaletteMigration(t *testing.T) {
	root := t.TempDir()
	config, state := filepath.Join(root, "config"), filepath.Join(root, `state with "quote"`)
	t.Setenv("XDG_CONFIG_HOME", config)
	t.Setenv("XDG_STATE_HOME", state)
	template := filepath.Join(config, "ryoku/user_edits/matugen/templates/vesktop-colors.css")
	ownership := filepath.Join(state, "ryoku/palette-bridge/owned-files.tsv")
	settings := filepath.Join(config, "vesktop/settings/settings.json")
	overlay := filepath.Join(config, "ryoku/user_edits/matugen/apps.toml")
	write := func(path, content string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	legacy := fmt.Sprintf("[config]\n\n[templates.vesktop]\ninput_path = %q\noutput_path = %q\n", filepath.Join(config, "matugen/templates/vesktop-colors.css"), filepath.Join(config, "vesktop/settings/quickCss.css"))
	write(overlay, legacy)
	write(settings, `{"useQuickCss":true}`)
	if legacyVesktopPalette(config, state) {
		t.Fatal("unowned integration selected")
	}
	write(ownership, "vesktop\t"+template+"\n")
	if !legacyVesktopPalette(config, state) {
		t.Fatal("owned legacy registration not selected")
	}
	for _, raw := range []string{`{}`, `{"useQuickCss":false}`, `invalid`} {
		write(settings, raw)
		if legacyVesktopPalette(config, state) {
			t.Fatalf("disabled/invalid settings selected: %s", raw)
		}
	}
	write(settings, `{"useQuickCss":true}`)
	for _, raw := range []string{legacy + "post_hook = \"custom\"\n", "[config]\n", legacy + "# customized\n"} {
		write(overlay, raw)
		if legacyVesktopPalette(config, state) {
			t.Fatal("edited/missing registration selected")
		}
	}
	write(overlay, legacy)
	installer := filepath.Join(root, "installer.sh")

	mergeRoot := filepath.Join(state, "ryoku/palette-bridge/vesktop")
	sourceHelper := filepath.Join(root, "vesktop/quickcss.sh")
	write(sourceHelper, "# preserving helper fixture\n")
	write(filepath.Join(mergeRoot, "quickcss.sh"), "# preserving helper fixture\n")
	hook := fmt.Sprintf("bash '%s' '%s' '%s'", filepath.Join(mergeRoot, "quickcss.sh"), filepath.Join(config, "vesktop/settings/quickCss.css"), filepath.Join(mergeRoot, "palette.css"))
	encoded, _ := json.Marshal(hook)
	upgraded := filepath.Join(root, "upgraded.toml")
	write(upgraded, fmt.Sprintf("[templates.vesktop]\noutput_path = %q\npost_hook = %s\n", filepath.Join(mergeRoot, "palette.css"), encoded))
	capability := "if [ \"$1\" = --capabilities ]; then printf 'vesktop-preserve-quickcss-v1\\n'; exit 0; fi\n"
	write(installer, capability+fmt.Sprintf("[ \"$1\" = --vesktop ] || exit 2\ncp %q \"$XDG_CONFIG_HOME/ryoku/user_edits/matugen/apps.toml\"\n", upgraded))

	old := vesktopPaletteInstaller
	vesktopPaletteInstaller = installer
	t.Cleanup(func() { vesktopPaletteInstaller = old })
	if r := reconcileVesktopPalette(true); r.status != recWouldFix {
		t.Fatalf("check-only: %+v", r)
	}
	if !legacyVesktopPalette(config, state) {
		t.Fatal("check-only mutated registration")
	}

	vesktopPaletteInstaller = filepath.Join(root, "missing-installer.sh")
	if r := reconcileVesktopPalette(false); r.status != recWarn {
		t.Fatalf("missing helper: %+v", r)
	}
	vesktopPaletteInstaller = installer
	workingInstaller, err := os.ReadFile(installer)
	if err != nil {
		t.Fatal(err)
	}
	write(installer, capability+"exit 42\n")
	if r := reconcileVesktopPalette(false); r.status != recFailed {
		t.Fatalf("failing helper: %+v", r)
	}
	write(installer, "exit 0\n")
	if r := reconcileVesktopPalette(false); r.status != recWarn {
		t.Fatalf("old helper: %+v", r)
	}
	write(installer, capability+"exit 0\n")
	if r := reconcileVesktopPalette(false); r.status != recFailed {
		t.Fatalf("old/no-op helper: %+v", r)
	}
	if !legacyVesktopPalette(config, state) {
		t.Fatal("failure tests changed registration")
	}

	write(installer, capability+"printf '[config]\\n' > \"$XDG_CONFIG_HOME/ryoku/user_edits/matugen/apps.toml\"\n")
	if r := reconcileVesktopPalette(false); r.status != recFailed {
		t.Fatalf("deleted registration: %+v", r)
	}
	write(overlay, legacy)
	write(installer, string(workingInstaller))
	if r := reconcileVesktopPalette(false); r.status != recFixed {
		t.Fatalf("repair: %+v", r)
	}
	if legacyVesktopPalette(config, state) {
		t.Fatal("migration did not invoke installer")
	}
	write(installer, "exit 99\n")
	if r := reconcileVesktopPalette(false); r.status != recOK {
		t.Fatalf("repeat: %+v", r)
	}
}

func TestVesktopPaletteDefaultHomeRegistration(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", "")
	t.Setenv("XDG_STATE_HOME", "")
	config, state := filepath.Join(home, ".config"), filepath.Join(home, ".local/state")
	files := map[string]string{
		filepath.Join(config, "vesktop/settings/settings.json"):      `{"useQuickCss":true}`,
		filepath.Join(state, "ryoku/palette-bridge/owned-files.tsv"): "vesktop\t" + filepath.Join(config, "ryoku/user_edits/matugen/templates/vesktop-colors.css") + "\n",
		filepath.Join(config, "ryoku/user_edits/matugen/apps.toml"):  "[templates.vesktop]\ninput_path = \"~/.config/matugen/templates/vesktop-colors.css\"\noutput_path = \"~/.config/vesktop/settings/quickCss.css\"\n",
	}
	for path, content := range files {
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	if !legacyVesktopPalette(config, state) {
		t.Fatal("default-home tilde registration not selected")
	}
}
