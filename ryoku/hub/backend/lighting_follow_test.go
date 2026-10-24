package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFollowChoosesStaticAndPaintsAccent(t *testing.T) {
	setupFollowTest(t)
	device := followTestDevice("Colourless board", []orgbMode{
		{Name: "Wave", Value: 3, Flags: modeHasSpeed},
		{Name: "Static", Value: 0, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
	})
	key := deviceKey(device)
	stubLightingAccess(t, []orgbDevice{device})

	oldWrite := auraWrite
	defer func() { auraWrite = oldWrite }()
	var painted auraEffect
	auraWrite = func(_ string, effect auraEffect, _ int) error {
		painted = effect
		return nil
	}

	out := captureStdout(t, func() {
		if err := lightingFollow(key, true); err != nil {
			t.Fatal(err)
		}
	})
	var report lightReport
	if err := json.Unmarshal([]byte(out), &report); err != nil {
		t.Fatalf("follow printed %q: %v", out, err)
	}

	settings := loadLighting().Devices[key]
	if settings == nil || !settings.Managed || settings.Source != "accent" {
		t.Fatalf("follow settings = %+v", settings)
	}
	if settings.Mode != "Static" || settings.Restore != "Wave" {
		t.Fatalf("mode = %q, restore = %q", settings.Mode, settings.Restore)
	}
	if painted.Mode != 0 || painted.Colour1 != (auraColour{R: 0xF2, G: 0x56, B: 0x23}) {
		t.Fatalf("painted effect = %+v", painted)
	}
	if len(report.Devices) != 1 || !report.Devices[0].Following {
		t.Fatalf("follow report = %+v", report.Devices)
	}
}

func TestFollowKeepsStoredColourMode(t *testing.T) {
	setupFollowTest(t)
	device := followTestDevice("Mode keeper", []orgbMode{
		{Name: "Wave", Value: 3, Flags: modeHasSpeed},
		{Name: "Glow", Value: 7, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
		{Name: "Static", Value: 0, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
	})
	key := deviceKey(device)
	if err := saveLighting(lightingState{Enabled: true, Devices: map[string]*lightingSettings{
		key: {Name: device.Name, Mode: "Glow", Source: "fixed", Brightness: -1, Speed: -1, Restore: "Wave"},
	}}); err != nil {
		t.Fatal(err)
	}
	stubLightingAccess(t, []orgbDevice{device})

	oldWrite := auraWrite
	defer func() { auraWrite = oldWrite }()
	gotMode := uint32(99)
	auraWrite = func(_ string, effect auraEffect, _ int) error {
		gotMode = effect.Mode
		return nil
	}

	captureStdout(t, func() {
		if err := lightingFollow(key, true); err != nil {
			t.Fatal(err)
		}
	})
	settings := loadLighting().Devices[key]
	if settings.Mode != "Glow" || settings.Source != "accent" || !settings.Managed {
		t.Fatalf("follow settings = %+v", settings)
	}
	if gotMode != 7 {
		t.Fatalf("applied mode = %d, want stored Glow mode 7", gotMode)
	}
}

func TestFollowAllSkipsDevicesWithoutColour(t *testing.T) {
	setupFollowTest(t)
	good := followTestDevice("Colour board", []orgbMode{
		{Name: "Static", Value: 0, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
	})
	bad := followTestDevice("No-colour board", []orgbMode{
		{Name: "Wave", Value: 3, Flags: modeHasSpeed},
	})
	stubLightingAccess(t, []orgbDevice{good, bad})

	oldWrite := auraWrite
	defer func() { auraWrite = oldWrite }()
	writes := 0
	auraWrite = func(_ string, _ auraEffect, _ int) error {
		writes++
		return nil
	}

	out := captureStdout(t, func() {
		if err := lightingFollow("--all", true); err != nil {
			t.Fatal(err)
		}
	})
	var report lightReport
	if err := json.Unmarshal([]byte(out), &report); err != nil {
		t.Fatalf("follow --all printed %q: %v", out, err)
	}
	if writes != 1 {
		t.Fatalf("writes = %d, want only the colour-capable device", writes)
	}
	if !strings.Contains(report.Error, bad.Name) {
		t.Fatalf("error = %q, want skipped device name", report.Error)
	}
	state := loadLighting()
	if !state.Devices[deviceKey(good)].Managed {
		t.Fatal("colour-capable device was not adopted")
	}
	if state.Devices[deviceKey(bad)].Managed {
		t.Fatal("colourless device must remain unmanaged")
	}
}

func TestFollowWhileLightingOffDoesNotWrite(t *testing.T) {
	setupFollowTest(t)
	device := followTestDevice("Off board", []orgbMode{
		{Name: "Static", Value: 0, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
	})
	key := deviceKey(device)
	if err := saveLighting(lightingState{Devices: map[string]*lightingSettings{
		key: {Name: device.Name, Mode: "Static", Source: "fixed", Brightness: -1, Speed: -1},
	}}); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(lightingPath())
	if err != nil {
		t.Fatal(err)
	}

	called := false
	oldAccess := lightingAccess
	defer func() { lightingAccess = oldAccess }()
	lightingAccess = func(bool, bool, lightingProviders, func(*orgbConn, []orgbDevice) error) error {
		called = true
		return nil
	}

	out := captureStdout(t, func() {
		if err := lightingFollow(key, true); err != nil {
			t.Fatal(err)
		}
	})
	var report lightReport
	if err := json.Unmarshal([]byte(out), &report); err != nil {
		t.Fatalf("follow printed %q: %v", out, err)
	}
	if report.Error != "Lighting is off." {
		t.Fatalf("error = %q", report.Error)
	}
	if called {
		t.Fatal("lighting-off follow touched a provider")
	}
	after, err := os.ReadFile(lightingPath())
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatal("lighting-off follow changed saved state")
	}
}

func TestFollowOffRestoresAndReleasesDevice(t *testing.T) {
	setupFollowTest(t)
	device := followTestDevice("Release board", []orgbMode{
		{Name: "Static", Value: 0, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
		{Name: "Wave", Value: 9, Flags: modeHasSpeed},
	})
	key := deviceKey(device)
	if err := saveLighting(lightingState{Enabled: true, Devices: map[string]*lightingSettings{
		key: {
			Name: device.Name, Managed: true, Mode: "Static", Source: "accent",
			Brightness: -1, Speed: -1, Restore: "Wave",
		},
	}}); err != nil {
		t.Fatal(err)
	}
	stubLightingAccess(t, []orgbDevice{device})

	oldRestore := auraRestore
	defer func() { auraRestore = oldRestore }()
	restored := uint32(99)
	auraRestore = func(_ string, mode uint32) error {
		restored = mode
		return nil
	}

	out := captureStdout(t, func() {
		if err := lightingFollow(key, false); err != nil {
			t.Fatal(err)
		}
	})
	var report lightReport
	if err := json.Unmarshal([]byte(out), &report); err != nil {
		t.Fatalf("follow off printed %q: %v", out, err)
	}
	if restored != 9 {
		t.Fatalf("restored mode = %d, want 9", restored)
	}
	if loadLighting().Devices[key].Managed {
		t.Fatal("follow off kept the device managed")
	}
	if len(report.Devices) != 1 || report.Devices[0].Following {
		t.Fatalf("release report = %+v", report.Devices)
	}
}

func TestFollowOffAllReleasesEveryManagedDevice(t *testing.T) {
	setupFollowTest(t)
	first := followTestDevice("First board", []orgbMode{
		{Name: "Static", Value: 0, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
		{Name: "Wave", Value: 4, Flags: modeHasSpeed},
	})
	second := followTestDevice("Second board", []orgbMode{
		{Name: "Static", Value: 0, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
		{Name: "Wave", Value: 8, Flags: modeHasSpeed},
	})
	if err := saveLighting(lightingState{Enabled: true, Devices: map[string]*lightingSettings{
		deviceKey(first): {
			Name: first.Name, Managed: true, Mode: "Static", Source: "accent",
			Brightness: -1, Speed: -1, Restore: "Wave",
		},
		deviceKey(second): {
			Name: second.Name, Managed: true, Mode: "Static", Source: "accent",
			Brightness: -1, Speed: -1, Restore: "Wave",
		},
	}}); err != nil {
		t.Fatal(err)
	}
	stubLightingAccess(t, []orgbDevice{first, second})

	oldRestore := auraRestore
	defer func() { auraRestore = oldRestore }()
	restored := map[string]uint32{}
	auraRestore = func(path string, mode uint32) error {
		restored[path] = mode
		return nil
	}

	out := captureStdout(t, func() {
		if err := lightingFollow("--all", false); err != nil {
			t.Fatal(err)
		}
	})
	var report lightReport
	if err := json.Unmarshal([]byte(out), &report); err != nil {
		t.Fatalf("follow --all off printed %q: %v", out, err)
	}
	if restored[first.ProviderPath] != 4 || restored[second.ProviderPath] != 8 {
		t.Fatalf("restored modes = %+v", restored)
	}
	state := loadLighting()
	if !state.Enabled || state.Devices[deviceKey(first)].Managed || state.Devices[deviceKey(second)].Managed {
		t.Fatalf("released state = %+v", state)
	}
	if report.Error != "" {
		t.Fatalf("release error = %q", report.Error)
	}
}

func TestFollowKeepsOpenRGBEffect(t *testing.T) {
	device := orgbDevice{
		Name: "Effect board",
		Modes: []orgbMode{
			{Name: "Direct", Flags: modeHasPerLEDColor},
		},
	}
	settings := &lightingSettings{Effect: "breathe", Mode: "Direct", Source: "fixed"}
	if !prepareFollow(device, settings) {
		t.Fatal("paintable OpenRGB device was skipped")
	}
	if settings.Effect != "breathe" || settings.Mode != "Direct" {
		t.Fatalf("OpenRGB follow settings = %+v", settings)
	}
	if !settings.Managed || settings.Source != "accent" {
		t.Fatalf("OpenRGB device was not set to follow: %+v", settings)
	}
}

func TestFollowUsesFirmwareModesForNativeDevices(t *testing.T) {
	device := followTestDevice("Native board", []orgbMode{
		{Name: "Static", Value: 0, Flags: modeHasModeColor, ColorsMin: 1, ColorsMax: 1},
	})
	settings := &lightingSettings{Effect: "breathe", Mode: "Wave", Source: "fixed"}
	if !prepareFollow(device, settings) {
		t.Fatal("native colour-capable device was skipped")
	}
	if settings.Effect != "" || settings.Mode != "Static" {
		t.Fatalf("native follow settings = %+v", settings)
	}
	if !settings.Managed || settings.Source != "accent" {
		t.Fatalf("native device was not set to follow: %+v", settings)
	}
}

func TestFollowingFlagRequiresAccentManagedDevice(t *testing.T) {
	state := lightingState{Devices: map[string]*lightingSettings{
		"Accent":   {Name: "Accent", Managed: true, Source: "accent", Brightness: -1, Speed: -1},
		"Fixed":    {Name: "Fixed", Managed: true, Source: "fixed", Brightness: -1, Speed: -1},
		"Released": {Name: "Released", Source: "accent", Brightness: -1, Speed: -1},
	}}
	views := mergeViews([]orgbDevice{{Name: "Accent"}}, state)
	following := map[string]bool{}
	for _, device := range views {
		following[device.Key] = device.Following
	}
	if !following["Accent"] || following["Fixed"] || following["Released"] {
		t.Fatalf("following flags = %+v", following)
	}
}

func setupFollowTest(t *testing.T) {
	t.Helper()
	root := t.TempDir()
	bin := filepath.Join(root, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(root, "cache"))
	t.Setenv("XDG_RUNTIME_DIR", filepath.Join(root, "runtime"))
	if err := os.MkdirAll(filepath.Dir(palettePath()), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(palettePath(), []byte("return { active = \"#F25623\" }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := saveLighting(lightingState{Enabled: true, Devices: map[string]*lightingSettings{}}); err != nil {
		t.Fatal(err)
	}
}

func followTestDevice(name string, modes []orgbMode) orgbDevice {
	return orgbDevice{
		Provider:     auraProvider,
		ProviderPath: "/test/" + strings.ReplaceAll(name, " ", "-"),
		Name:         name,
		Serial:       auraProvider + ":" + name,
		ActiveMode:   0,
		Modes:        modes,
	}
}

func stubLightingAccess(t *testing.T, live []orgbDevice) {
	t.Helper()
	oldAccess := lightingAccess
	t.Cleanup(func() { lightingAccess = oldAccess })
	lightingAccess = func(_ bool, _ bool, _ lightingProviders, fn func(*orgbConn, []orgbDevice) error) error {
		return fn(nil, live)
	}
}
