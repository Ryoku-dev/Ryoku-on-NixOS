package ryokumanifest

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestChoicePackagesReadsInstallerChoices(t *testing.T) {
	path := filepath.Join(t.TempDir(), "choices.tsv")
	fixture := "record\tkind\tid\tlabel\tpackages\texecutable\tfresh\texisting\tshow_unavailable_iso\ttui_hint\tshell_detail\tflags\n" +
		"choice\tbrowser\tfirefox\tFirefox\tfirefox\t-\t-\t-\tfalse\t-\t-\t-\n" +
		"choice\tbrowser\tchromium\tChromium\tchromium\t-\t-\t-\tfalse\t-\t-\t-\n" +
		"choice\tbrowser\tzen\tZen\tzen-browser-bin\t-\t-\t-\tfalse\t-\t-\t-\n" +
		"choice\tcompositor\tniri\tniri\tryoku-desktop-niri,xwayland-satellite\t-\t-\t-\tfalse\t-\t-\t-\n" +
		"choice\tcompositor\tnone\tNone\t-\t-\t-\t-\tfalse\t-\t-\t-\n" +
		"policy\tbrowser\tfresh\t-\t-\t-\tfirefox\t-\t-\t-\t-\t-\n"
	if err := os.WriteFile(path, []byte(fixture), 0o600); err != nil {
		t.Fatal(err)
	}

	got, err := ChoicePackages(path)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{"firefox": true, "chromium": true, "zen-browser-bin": true,
		"ryoku-desktop-niri": true, "xwayland-satellite": true}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("packages = %#v, want %#v", got, want)
	}
}

func TestChoicePackagesRequiresFile(t *testing.T) {
	if _, err := ChoicePackages(filepath.Join(t.TempDir(), "missing.tsv")); err == nil {
		t.Fatal("missing choices file returned no error")
	}
}

func TestBuildExcludesInstallerChoicePackages(t *testing.T) {
	m := Build(Inputs{
		Base:    "firefox\nchromium\nkitty\n",
		Dev:     "chromium\n",
		AUR:     "zen-browser-bin\n",
		Choices: map[string]bool{"firefox": true, "chromium": true, "zen-browser-bin": true},
		FirstParty: map[string]string{
			"browser":  "pkgname=firefox\n",
			"terminal": "pkgname=kitty\n",
		},
	})

	if want := []string{"kitty"}; !reflect.DeepEqual(m.Base, want) {
		t.Errorf("base = %v, want %v", m.Base, want)
	}
	if len(m.Dev) != 0 {
		t.Errorf("dev = %v, want no installer choices", m.Dev)
	}
	if len(m.AUR) != 0 {
		t.Errorf("aur = %v, want no installer choices", m.AUR)
	}
	if want := []string{"kitty"}; !reflect.DeepEqual(m.FirstParty, want) {
		t.Errorf("firstParty = %v, want %v", m.FirstParty, want)
	}
	for _, name := range []string{"firefox", "chromium", "zen-browser-bin"} {
		if lane := m.Lane(name); lane != "" {
			t.Errorf("%s remained in %s", name, lane)
		}
	}
}
