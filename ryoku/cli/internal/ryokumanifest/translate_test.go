package ryokumanifest

import (
	"reflect"
	"strings"
	"testing"
)

func fedoraTable() map[string]Translation {
	return map[string]Translation{
		"base":         {Lanes: []string{"system"}},
		"linux":        {Names: []string{"kernel"}, Lanes: []string{"system"}},
		"base-devel":   {Names: []string{"gcc", "make"}, Lanes: []string{"system"}},
		"bluez":        {Names: []string{"bluez"}, Lanes: []string{"desktop"}},
		"bluez-utils":  {Names: []string{"bluez"}, Lanes: []string{"desktop"}},
		"snapper":      {Names: []string{"snapper"}, Lanes: []string{"desktop", "system"}},
		"libvirt":      {Names: []string{"libvirt"}, Lanes: []string{"optional"}},
		"go":           {Names: []string{"golang"}, Lanes: []string{"dev"}},
		"nodejs":       {Names: []string{"nodejs24"}, Lanes: []string{"desktop", "dev"}},
		"blesh":        {Names: []string{"blesh"}, Lanes: []string{"desktop"}},
		"ryoku-shell":  {Names: []string{"ryoku-shell"}, Lanes: []string{"desktop"}},
		"amd-ucode":    {Names: []string{"amd-ucode-firmware"}, Lanes: []string{"hardware:amd"}},
		"hyprland":     {Names: []string{"hyprland"}, Lanes: []string{"hyprland"}},
		"localsend":    {Names: []string{"localsend"}, Lanes: []string{"optional"}},
		"limine":       {Lanes: []string{"system"}},
		"xpadneo-dkms": {Names: []string{"xpadneo"}, Lanes: []string{"extra"}},
	}
}

func TestTranslateKeepsOnlyTheInstallerLane(t *testing.T) {
	m := Manifest{
		Base:       []string{"base", "base-devel", "bluez", "bluez-utils", "libvirt", "linux", "snapper"},
		Dev:        []string{"go", "nodejs"},
		AUR:        []string{"blesh", "xpadneo-dkms"},
		FirstParty: []string{"ryoku-shell"},
	}
	got, err := Translate(m, fedoraTable(), "desktop")
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"bluez", "snapper"}; !reflect.DeepEqual(got.Base, want) {
		t.Errorf("base = %v, want %v", got.Base, want)
	}
	if want := []string{"nodejs24"}; !reflect.DeepEqual(got.Dev, want) {
		t.Errorf("dev = %v, want %v", got.Dev, want)
	}
	if want := []string{"blesh"}; !reflect.DeepEqual(got.AUR, want) {
		t.Errorf("aur = %v, want %v", got.AUR, want)
	}
	if want := []string{"ryoku-shell"}; !reflect.DeepEqual(got.FirstParty, want) {
		t.Errorf("firstParty = %v, want %v", got.FirstParty, want)
	}
}

func TestTranslateNamesTheUnconvergedLanesUnfiltered(t *testing.T) {
	m := Manifest{
		Release:     "v1",
		Hardware:    map[string][]string{"amd": {"amd-ucode"}, "none": {"limine"}},
		Compositor:  map[string][]string{"hyprland": {"hyprland"}},
		Provisioned: []string{"localsend"},
	}
	got, err := Translate(m, fedoraTable(), "desktop")
	if err != nil {
		t.Fatal(err)
	}
	if got.Release != "v1" {
		t.Errorf("release = %q, want the metadata carried over", got.Release)
	}
	if want := map[string][]string{"amd": {"amd-ucode-firmware"}}; !reflect.DeepEqual(got.Hardware, want) {
		t.Errorf("hardware = %v, want %v", got.Hardware, want)
	}
	if want := map[string][]string{"hyprland": {"hyprland"}}; !reflect.DeepEqual(got.Compositor, want) {
		t.Errorf("compositor = %v, want %v", got.Compositor, want)
	}
	if want := []string{"localsend"}; !reflect.DeepEqual(got.Provisioned, want) {
		t.Errorf("provisioned = %v, want %v", got.Provisioned, want)
	}
}

func TestTranslateRejectsUntranslatedNames(t *testing.T) {
	m := Manifest{Base: []string{"bluez", "mystery"}, AUR: []string{"mystery", "phantom"}}
	_, err := Translate(m, fedoraTable(), "desktop")
	if err == nil || !strings.Contains(err.Error(), "no translation row for mystery, phantom") {
		t.Fatalf("err = %v, want the untranslated names listed once", err)
	}
}
