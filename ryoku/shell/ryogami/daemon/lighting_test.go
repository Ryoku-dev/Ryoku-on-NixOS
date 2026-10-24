package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

const lightingTestReport = `{"available":true,"enabled":true,"server":true,"accent":"#abcdef","devices":[]}`

func newLightingTestDaemon(t *testing.T, script string) (*daemon, <-chan string) {
	t.Helper()
	root := t.TempDir()
	bin := filepath.Join(root, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	hub := filepath.Join(bin, "ryoku-hub")
	if err := os.WriteFile(hub, []byte("#!/bin/sh\n"+script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))
	t.Setenv("HOME", root)
	t.Setenv("XDG_CACHE_HOME", filepath.Join(root, "cache"))
	d := &daemon{events: newEventHub()}
	events := d.events.subscribe()
	t.Cleanup(func() {
		d.events.unsubscribe(events)
		if value, ok := lightingControllers.LoadAndDelete(d); ok {
			close(value.(*lightingController).stop)
		}
	})
	return d, events
}

func nextLightingEvent(t *testing.T, events <-chan string) lightingSnapshot {
	t.Helper()
	select {
	case line := <-events:
		var frame struct {
			Event string           `json:"event"`
			Data  lightingSnapshot `json:"data"`
		}
		if err := json.Unmarshal([]byte(line), &frame); err != nil {
			t.Fatalf("decode lighting event: %v: %s", err, line)
		}
		if frame.Event != "ryogami.lighting" {
			t.Fatalf("event = %q, want ryogami.lighting", frame.Event)
		}
		return frame.Data
	case <-time.After(3 * time.Second):
		t.Fatal("timed out waiting for lighting event")
		return lightingSnapshot{}
	}
}

func waitLightingIdle(t *testing.T, events <-chan string) lightingSnapshot {
	t.Helper()
	deadline := time.After(4 * time.Second)
	for {
		select {
		case line := <-events:
			var frame struct {
				Event string           `json:"event"`
				Data  lightingSnapshot `json:"data"`
			}
			if err := json.Unmarshal([]byte(line), &frame); err != nil {
				t.Fatalf("decode lighting event: %v: %s", err, line)
			}
			if frame.Event == "ryogami.lighting" && !frame.Data.Busy {
				return frame.Data
			}
		case <-deadline:
			t.Fatal("timed out waiting for lighting to become idle")
			return lightingSnapshot{}
		}
	}
}

func TestLightingRPCRepliesBeforeCommandCompletesAndBroadcastsState(t *testing.T) {
	d, events := newLightingTestDaemon(t, "sleep 1\nprintf '%s\\n' '"+lightingTestReport+"'\n")
	req := &request{ID: 7, Method: "lighting.state"}

	startedAt := time.Now()
	resp, handled := d.dispatchExtended(req, map[string]interface{}{})
	elapsed := time.Since(startedAt)
	if !handled || resp.Error != nil {
		t.Fatalf("response = %#v, handled = %v", resp, handled)
	}
	if elapsed >= 100*time.Millisecond {
		t.Fatalf("lighting.state blocked for %s", elapsed)
	}
	queued, ok := resp.Result.(lightingSnapshot)
	if !ok || !queued.Hub || !queued.Busy {
		t.Fatalf("queued snapshot = %#v", resp.Result)
	}

	busy := nextLightingEvent(t, events)
	if !busy.Busy || busy.Op != "state" || busy.Seq != 1 {
		t.Fatalf("start event = %#v", busy)
	}
	idle := nextLightingEvent(t, events)
	if idle.Busy || idle.Op != "" || idle.Error != "" || idle.Seq != 2 {
		t.Fatalf("finish event = %#v", idle)
	}
	if idle.Report["accent"] != "#abcdef" {
		t.Fatalf("report = %#v", idle.Report)
	}
}

func TestLightingQueuedSetsMergeByDevice(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "argv.log")
	t.Setenv("RYOGAMI_LIGHTING_ARGV_LOG", logPath)
	script := "printf '%s\\n' \"$*\" >> \"$RYOGAMI_LIGHTING_ARGV_LOG\"\n" +
		"if [ \"$2\" = scan ]; then sleep 1; fi\n" +
		"printf '%s\\n' '" + lightingTestReport + "'\n"
	d, events := newLightingTestDaemon(t, script)

	d.dispatchLighting(&request{ID: 1, Method: "lighting.scan"}, map[string]interface{}{})
	if started := nextLightingEvent(t, events); started.Op != "scan" || !started.Busy {
		t.Fatalf("scan start = %#v", started)
	}
	d.dispatchLighting(&request{ID: 2, Method: "lighting.set"}, map[string]interface{}{
		"key": "keyboard",
		"patch": map[string]interface{}{
			"brightness": float64(25),
			"source":     "fixed",
		},
	})
	d.dispatchLighting(&request{ID: 3, Method: "lighting.set"}, map[string]interface{}{
		"key": "keyboard",
		"patch": map[string]interface{}{
			"brightness": float64(80),
			"speed":      float64(40),
		},
	})
	idle := waitLightingIdle(t, events)
	if idle.Error != "" {
		t.Fatalf("finish error = %q", idle.Error)
	}

	content, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	var sets []string
	for _, line := range strings.Split(strings.TrimSpace(string(content)), "\n") {
		if strings.HasPrefix(line, "lighting set keyboard ") {
			sets = append(sets, line)
		}
	}
	if len(sets) != 1 {
		t.Fatalf("set invocations = %d, log:\n%s", len(sets), content)
	}
	var patch map[string]interface{}
	if err := json.Unmarshal([]byte(strings.TrimPrefix(sets[0], "lighting set keyboard ")), &patch); err != nil {
		t.Fatalf("set patch: %v", err)
	}
	if patch["brightness"] != float64(80) || patch["source"] != "fixed" || patch["speed"] != float64(40) {
		t.Fatalf("merged patch = %#v", patch)
	}
}

func TestLightingCommandErrorUsesLastStderrLine(t *testing.T) {
	d, events := newLightingTestDaemon(t, "printf '%s\\n' first failure >&2\nprintf '%s\\n' 'device failed' >&2\nexit 7\n")
	d.dispatchLighting(&request{ID: 1, Method: "lighting.state"}, map[string]interface{}{})
	idle := waitLightingIdle(t, events)
	if idle.Error != "device failed" {
		t.Fatalf("error = %q", idle.Error)
	}
	if idle.Report != nil {
		t.Fatalf("report = %#v, want nil", idle.Report)
	}
}

func TestLightingCommandTimeoutIsReported(t *testing.T) {
	d, events := newLightingTestDaemon(t, "sleep 2\nprintf '%s\\n' '"+lightingTestReport+"'\n")
	controller := lightingControllerFor(d)
	controller.timeouts.state = 40 * time.Millisecond

	d.dispatchLighting(&request{ID: 1, Method: "lighting.state"}, map[string]interface{}{})
	idle := waitLightingIdle(t, events)
	if !strings.Contains(idle.Error, "timed out") {
		t.Fatalf("error = %q", idle.Error)
	}
}

func lightingTestDevice(t *testing.T, report map[string]interface{}, key string) map[string]interface{} {
	t.Helper()
	rawDevices, ok := report["devices"].([]interface{})
	if !ok {
		t.Fatalf("devices = %#v", report["devices"])
	}
	for _, raw := range rawDevices {
		device, ok := raw.(map[string]interface{})
		if ok && device["key"] == key {
			return device
		}
	}
	t.Fatalf("device %q not found in %#v", key, rawDevices)
	return nil
}

func TestLightingStateKeepsLiveDevicesAndMergesSavedSettings(t *testing.T) {
	const scanReport = `{"available":true,"enabled":true,"server":true,"accent":"#111111","devices":[{"key":"board","name":"Live Board","vendor":"Live Vendor","type":"keyboard","description":"Live Description","location":"usb:1","online":true,"active":"Wave","modes":[{"name":"Wave"}],"effects":[{"id":"solid"}],"zones":[{"id":"keys"}],"managed":false,"following":false,"mode":"Wave","effect":"old","source":"fixed","colors":["#111111"],"zoneColors":{"keys":"#222222"},"brightness":10,"speed":20,"direction":"left","restore":"Direct"}]}`
	const stateReport = `{"available":false,"enabled":true,"server":false,"accent":"#ABCDEF","error":"saved status","devices":[{"key":"board","name":"Saved Board","online":false,"managed":true,"following":true,"mode":"Static","source":"accent","colors":["#ABCDEF"],"zoneColors":{"keys":"#FEDCBA"},"brightness":80,"speed":70,"direction":"right","restore":"Wave"}]}`
	script := "case \"$2\" in\n" +
		"scan) printf '%s\\n' '" + scanReport + "' ;;\n" +
		"state) printf '%s\\n' '" + stateReport + "' ;;\n" +
		"esac\n"
	d, events := newLightingTestDaemon(t, script)

	d.dispatchLighting(&request{ID: 1, Method: "lighting.scan"}, map[string]interface{}{})
	if scan := waitLightingIdle(t, events); lightingTestDevice(t, scan.Report, "board")["online"] != true {
		t.Fatalf("scan report = %#v", scan.Report)
	}
	d.dispatchLighting(&request{ID: 2, Method: "lighting.state"}, map[string]interface{}{})
	state := waitLightingIdle(t, events)
	device := lightingTestDevice(t, state.Report, "board")

	for field, want := range map[string]interface{}{
		"online": true, "active": "Wave", "vendor": "Live Vendor", "type": "keyboard",
		"description": "Live Description", "location": "usb:1",
	} {
		if got := device[field]; got != want {
			t.Errorf("%s = %#v, want %#v", field, got, want)
		}
	}
	for field, want := range map[string]interface{}{
		"name": "Saved Board", "managed": true, "following": true, "mode": "Static",
		"source": "accent", "brightness": float64(80), "speed": float64(70),
		"direction": "right", "restore": "Wave",
	} {
		if got := device[field]; got != want {
			t.Errorf("%s = %#v, want %#v", field, got, want)
		}
	}
	for field, want := range map[string]interface{}{
		"modes":      []interface{}{map[string]interface{}{"name": "Wave"}},
		"effects":    []interface{}{map[string]interface{}{"id": "solid"}},
		"zones":      []interface{}{map[string]interface{}{"id": "keys"}},
		"colors":     []interface{}{"#ABCDEF"},
		"zoneColors": map[string]interface{}{"keys": "#FEDCBA"},
	} {
		if got := device[field]; !reflect.DeepEqual(got, want) {
			t.Errorf("%s = %#v, want %#v", field, got, want)
		}
	}
	if _, exists := device["effect"]; exists {
		t.Errorf("effect was not cleared: %#v", device["effect"])
	}
	for field, want := range map[string]interface{}{
		"available": false, "enabled": true, "server": false, "accent": "#ABCDEF", "error": "saved status",
	} {
		if got := state.Report[field]; got != want {
			t.Errorf("report %s = %#v, want %#v", field, got, want)
		}
	}
}

func TestLightingStateWhileDisabledReplacesLiveReport(t *testing.T) {
	const scanReport = `{"available":true,"enabled":true,"server":true,"accent":"#111111","devices":[{"key":"board","name":"Live Board","vendor":"Live Vendor","online":true,"active":"Wave","modes":[{"name":"Wave"}],"managed":true,"following":true,"brightness":50,"speed":50}]}`
	const stateReport = `{"available":true,"enabled":false,"server":false,"accent":"#222222","devices":[{"key":"board","name":"Saved Board","online":false,"managed":false,"following":false,"brightness":25,"speed":30}]}`
	script := "case \"$2\" in\n" +
		"scan) printf '%s\\n' '" + scanReport + "' ;;\n" +
		"state) printf '%s\\n' '" + stateReport + "' ;;\n" +
		"esac\n"
	d, events := newLightingTestDaemon(t, script)

	d.dispatchLighting(&request{ID: 1, Method: "lighting.scan"}, map[string]interface{}{})
	waitLightingIdle(t, events)
	d.dispatchLighting(&request{ID: 2, Method: "lighting.state"}, map[string]interface{}{})
	state := waitLightingIdle(t, events)
	device := lightingTestDevice(t, state.Report, "board")

	if state.Report["enabled"] != false || device["online"] != false || device["name"] != "Saved Board" {
		t.Fatalf("disabled state = %#v", state.Report)
	}
	for _, field := range []string{"vendor", "active", "modes"} {
		if _, exists := device[field]; exists {
			t.Errorf("disabled state retained %s: %#v", field, device[field])
		}
	}
}

func TestLightingStateAppendsSavedOfflineDevice(t *testing.T) {
	const scanReport = `{"available":true,"enabled":true,"server":true,"accent":"#111111","devices":[{"key":"board","name":"Board","online":true,"managed":true,"following":true,"brightness":50,"speed":50}]}`
	const stateReport = `{"available":true,"enabled":true,"server":true,"accent":"#222222","devices":[{"key":"board","name":"Board","online":false,"managed":true,"following":true,"brightness":60,"speed":70},{"key":"mouse","name":"Saved Mouse","online":true,"managed":true,"following":false,"mode":"Static","brightness":35,"speed":45}]}`
	script := "case \"$2\" in\n" +
		"scan) printf '%s\\n' '" + scanReport + "' ;;\n" +
		"state) printf '%s\\n' '" + stateReport + "' ;;\n" +
		"esac\n"
	d, events := newLightingTestDaemon(t, script)

	d.dispatchLighting(&request{ID: 1, Method: "lighting.scan"}, map[string]interface{}{})
	waitLightingIdle(t, events)
	d.dispatchLighting(&request{ID: 2, Method: "lighting.state"}, map[string]interface{}{})
	state := waitLightingIdle(t, events)

	devices := state.Report["devices"].([]interface{})
	if len(devices) != 2 {
		t.Fatalf("devices = %#v", devices)
	}
	mouse := lightingTestDevice(t, state.Report, "mouse")
	if mouse["online"] != false || mouse["name"] != "Saved Mouse" || mouse["brightness"] != float64(35) {
		t.Fatalf("offline device = %#v", mouse)
	}
}

func TestLightingStateCoalescesWhileStateIsRunning(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "argv.log")
	t.Setenv("RYOGAMI_LIGHTING_ARGV_LOG", logPath)
	script := "printf '%s\\n' \"$*\" >> \"$RYOGAMI_LIGHTING_ARGV_LOG\"\n" +
		"if [ \"$2\" = state ]; then sleep 1; fi\n" +
		"printf '%s\\n' '" + lightingTestReport + "'\n"
	d, events := newLightingTestDaemon(t, script)

	d.dispatchLighting(&request{ID: 1, Method: "lighting.state"}, map[string]interface{}{})
	if started := nextLightingEvent(t, events); started.Op != "state" || !started.Busy {
		t.Fatalf("state start = %#v", started)
	}
	for id := 2; id <= 6; id++ {
		resp, handled := d.dispatchLighting(&request{ID: int64(id), Method: "lighting.state"}, map[string]interface{}{})
		if !handled || resp.Error != nil {
			t.Fatalf("response %d = %#v, handled = %v", id, resp, handled)
		}
	}
	waitLightingIdle(t, events)

	content, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	var states int
	for _, line := range strings.Split(strings.TrimSpace(string(content)), "\n") {
		if line == "lighting state" {
			states++
		}
	}
	if states != 1 {
		t.Fatalf("state invocations = %d, log:\n%s", states, content)
	}
}

func TestLightingPaletteWatcherStopsWhenRPCsGoIdleAndRestarts(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "argv.log")
	t.Setenv("RYOGAMI_LIGHTING_ARGV_LOG", logPath)
	script := "printf '%s\\n' \"$*\" >> \"$RYOGAMI_LIGHTING_ARGV_LOG\"\n" +
		"printf '%s\\n' '" + lightingTestReport + "'\n"
	d, events := newLightingTestDaemon(t, script)
	controller := lightingControllerFor(d)
	controller.paletteIdleWindow = 1200 * time.Millisecond

	palettePath := lightingPalettePath()
	if err := os.MkdirAll(filepath.Dir(palettePath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(palettePath, []byte("initial"), 0o644); err != nil {
		t.Fatal(err)
	}

	stateInvocations := func() int {
		content, err := os.ReadFile(logPath)
		if err != nil {
			if os.IsNotExist(err) {
				return 0
			}
			t.Fatal(err)
		}
		count := 0
		for _, line := range strings.Split(strings.TrimSpace(string(content)), "\n") {
			if line == "lighting state" {
				count++
			}
		}
		return count
	}
	waitForWatcherStop := func() {
		deadline := time.Now().Add(3 * time.Second)
		for {
			controller.mu.Lock()
			watching := controller.watchingPalette
			controller.mu.Unlock()
			if !watching {
				return
			}
			if time.Now().After(deadline) {
				t.Fatal("palette watcher did not stop after the idle window")
			}
			time.Sleep(20 * time.Millisecond)
		}
	}

	d.dispatchLighting(&request{ID: 1, Method: "lighting.state"}, map[string]interface{}{})
	waitLightingIdle(t, events)
	waitForWatcherStop()

	if err := os.WriteFile(palettePath, []byte("changed while idle"), 0o644); err != nil {
		t.Fatal(err)
	}
	time.Sleep(850 * time.Millisecond)
	if got := stateInvocations(); got != 1 {
		t.Fatalf("state invocations after idle palette change = %d, want 1", got)
	}

	d.dispatchLighting(&request{ID: 2, Method: "lighting.state"}, map[string]interface{}{})
	waitLightingIdle(t, events)
	time.Sleep(50 * time.Millisecond)
	if err := os.WriteFile(palettePath, []byte("changed after restart with a different size"), 0o644); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for stateInvocations() < 3 {
		if time.Now().After(deadline) {
			t.Fatalf("palette refresh did not resume; state invocations = %d", stateInvocations())
		}
		time.Sleep(20 * time.Millisecond)
	}
	waitLightingIdle(t, events)
	waitForWatcherStop()
}
