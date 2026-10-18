package main

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestPaletteBridgeSpotifySettings(t *testing.T) {
	d := newSettingsDaemon(t)
	defaults := map[string]interface{}{"neutralStyle": false, "accentStrength": float64(100), "surfaceTint": float64(5), "neutralText": true, "removeGradients": true, "surfaceBrightness": float64(50), "sidebarTint": float64(100), "playerTint": float64(100), "cardTint": float64(100), "accentButtons": true, "accentProgress": true, "accentLinks": true}
	for name, want := range defaults {
		key := "paletteBridge.spotify." + name
		spec, ok := specFor(key)
		if !ok || spec.Default != want {
			t.Fatalf("%s default: %+v", key, spec)
		}
	}
	for key, bounds := range map[string][]float64{"accentStrength": {0, 100}, "surfaceTint": {0, 20}, "surfaceBrightness": {0, 100}, "sidebarTint": {0, 100}, "playerTint": {0, 100}, "cardTint": {0, 100}} {
		for _, value := range []float64{bounds[0], bounds[1]} {
			if err := validateSetting("paletteBridge.spotify."+key, value); err != nil {
				t.Fatal(err)
			}
		}
		for _, value := range []float64{bounds[0] - 1, bounds[1] + 1} {
			if err := validateSetting("paletteBridge.spotify."+key, value); err == nil {
				t.Fatalf("accepted %s=%v", key, value)
			}
		}
	}
	values := map[string]interface{}{"neutralStyle": true, "accentStrength": float64(70), "surfaceTint": float64(12), "neutralText": false, "removeGradients": false, "surfaceBrightness": float64(65), "sidebarTint": float64(40), "playerTint": float64(20), "cardTint": float64(80), "accentButtons": false, "accentProgress": false, "accentLinks": false}
	for name, value := range values {
		if err := d.persistSetting("paletteBridge.spotify."+name, value); err != nil {
			t.Fatal(err)
		}
	}
	d.flushSettingsNow()
	persisted := readJSONFile(t, configPath())
	got, ok := lookupDotted(persisted, "paletteBridge.spotify")
	if !ok || !reflect.DeepEqual(got, values) {
		t.Fatalf("nested preferences not persisted: %#v", persisted)
	}
}

func TestPaletteBridgeTypedActions(t *testing.T) {
	d := newSettingsDaemon(t)
	root := t.TempDir()
	log := filepath.Join(root, "calls")
	t.Setenv("PALETTE_TEST_LOG", log)
	t.Setenv("PATH", root+":"+os.Getenv("PATH"))
	hub := filepath.Join(root, "ryoku-hub")
	script := `#!/bin/sh
printf '%s\n' "$*" >> "$PALETTE_TEST_LOG"
case "$2" in
 integration) [ "$#" = 5 ] || exit 12 ;;
 *) [ "$#" = 3 ] || exit 13 ;;
esac
if [ "$2" = status ]; then printf '%s' '{"enabled":true,"active":true,"healthy":false,"integrations":[]}'; else printf 'completed'; fi
`
	if err := os.WriteFile(hub, []byte(script), 0755); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(root, "recipe directory")
	if err := d.persistSetting("paletteBridgeSource", source); err != nil {
		t.Fatal(err)
	}
	cases := map[string]string{
		"PaletteBridgeSetup":  "install " + source + "\npalette-bridge service enable",
		"PaletteBridgeEnable": "service enable", "PaletteBridgeDisable": "service disable", "PaletteBridgeRestart": "service restart",
		"PaletteBridgeStatus": "status " + source, "PaletteBridgeDoctor": "doctor " + source,
	}
	for app, name := range map[string]string{"spotify": "Spotify", "zen": "Zen", "vesktop": "Vesktop"} {
		for verb, suffix := range map[string]string{"install": "Setup", "remove": "Remove"} {
			cases["PaletteBridge"+name+suffix] = "integration " + verb + " " + app + " " + source
		}
	}
	for id, want := range cases {
		if err := os.WriteFile(log, nil, 0644); err != nil {
			t.Fatal(err)
		}
		result, err := d.runAction(id, nil)
		if err != nil {
			t.Fatalf("%s: %v", id, err)
		}
		raw, _ := os.ReadFile(log)
		if got := strings.TrimSpace(string(raw)); got != "palette-bridge "+want {
			t.Fatalf("%s routed %q want %q", id, got, want)
		}
		if id == "PaletteBridgeStatus" {
			m := result.(map[string]interface{})
			if m["healthy"] != false || m["active"] != true {
				t.Fatalf("lost hub status: %#v", m)
			}
		}
	}
	if err := os.WriteFile(hub, []byte("#!/bin/sh\nprintf 'fixture failure' >&2\nexit 9\n"), 0755); err != nil {
		t.Fatal(err)
	}
	for id := range cases {
		if _, err := d.runAction(id, nil); err == nil || !strings.Contains(err.Error(), "fixture failure") {
			t.Fatalf("%s swallowed failure: %v", id, err)
		}
	}

	if err := os.WriteFile(log, nil, 0644); err != nil {
		t.Fatal(err)
	}
	failInstall := `#!/bin/sh
printf '%s\n' "$*" >> "$PALETTE_TEST_LOG"
exit 9
`
	if err := os.WriteFile(hub, []byte(failInstall), 0755); err != nil {
		t.Fatal(err)
	}
	if _, err := d.runAction("PaletteBridgeSetup", nil); err == nil {
		t.Fatal("setup swallowed install failure")
	}
	raw, _ := os.ReadFile(log)
	if strings.TrimSpace(string(raw)) != "palette-bridge install "+source {
		t.Fatalf("setup continued after failure: %s", raw)
	}
	if err := os.WriteFile(hub, []byte("#!/bin/sh\nprintf 'not json'\n"), 0755); err != nil {
		t.Fatal(err)
	}
	if _, err := d.runAction("PaletteBridgeStatus", nil); err == nil {
		t.Fatal("accepted malformed status")
	}
}
