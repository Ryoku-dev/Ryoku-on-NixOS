package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestNextUpdateWake(t *testing.T) {
	day := 24 * time.Hour
	cases := []struct {
		name        string
		since, full time.Duration
		alerts      bool
		wait        time.Duration
		probe       bool
	}{
		{"daily probes hourly", 0, day, true, time.Hour, true},
		{"probe again after a quiet probe", 5 * time.Hour, day, true, time.Hour, true},
		{"last hour runs the check", day - 30*time.Minute, day, true, 30 * time.Minute, false},
		{"overdue check runs now", 2 * day, day, true, 0, false},
		{"hourly checks need no probe", 0, time.Hour, true, time.Hour, false},
		{"alerts off keeps the old cadence", 0, day, false, day, false},
		{"checks off", 0, 0, true, -1, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			wait, probe := nextUpdateWake(tc.since, tc.full, tc.alerts)
			if wait != tc.wait || probe != tc.probe {
				t.Errorf("nextUpdateWake(%v, %v, %v) = %v, %v; want %v, %v", tc.since, tc.full, tc.alerts, wait, probe, tc.wait, tc.probe)
			}
		})
	}
}

// stubRyokuStatus answers `ryoku status --json` with full and `ryoku status
// --urgent --json` with probe, and records each call.
func stubRyokuStatus(t *testing.T, full, probe *string, probeErr *error) *[]string {
	t.Helper()
	calls := []string{}
	previous := ryokuStatus
	t.Cleanup(func() { ryokuStatus = previous })
	ryokuStatus = func(args ...string) ([]byte, error) {
		calls = append(calls, strings.Join(args, " "))
		if len(args) > 0 && args[0] == "--urgent" {
			if *probeErr != nil {
				return nil, *probeErr
			}
			return []byte(*probe), nil
		}
		return []byte(*full), nil
	}
	return &calls
}

func TestUrgentProbeWantsACheckOnlyForANewCommit(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	full := `{"available":true,"urgent":[{"commit":"aaaaaaa","reason":"first"}]}`
	probe := `{"urgent":[{"commit":"aaaaaaa"}]}`
	var probeErr error
	calls := stubRyokuStatus(t, &full, &probe, &probeErr)

	s := &updatesState{topic: newStateTopic()}
	s.check()
	if got := string(s.topic.last); got != full {
		t.Fatalf("published frame = %s, want the full status", got)
	}
	cached, err := os.ReadFile(filepath.Join(os.Getenv("XDG_CACHE_HOME"), "ryoku", "update-status.json"))
	if err != nil || string(cached) != full {
		t.Fatalf("cache = %q, %v; want the full status", cached, err)
	}

	if s.urgentNews() {
		t.Error("a probe that lists only the known commit is no news")
	}
	probe = `{"urgent":[{"commit":"bbbbbbb"},{"commit":"aaaaaaa"}]}`
	if !s.urgentNews() {
		t.Error("a probe that lists a new urgent commit is news")
	}
	probe = `{"urgent":[]}`
	if s.urgentNews() {
		t.Error("an empty probe is no news")
	}
	probeErr = errors.New("offline")
	probe = `{"urgent":[{"commit":"ccccccc"}]}`
	if s.urgentNews() {
		t.Error("a failed probe is no news")
	}
	want := []string{"--json", "--urgent --json", "--urgent --json", "--urgent --json", "--urgent --json"}
	if strings.Join(*calls, "|") != strings.Join(want, "|") {
		t.Errorf("calls = %q, want %q", *calls, want)
	}
}

func TestUrgentSetIgnoresAnythingElse(t *testing.T) {
	for _, frame := range []string{``, `not json`, `{"available":true}`, `{"urgent":null}`, `{"urgent":[{"commit":""}]}`} {
		if got := urgentSet([]byte(frame)); len(got) != 0 {
			t.Errorf("urgentSet(%q) = %v, want empty", frame, got)
		}
	}
}

func TestUrgentAlertsFollowTheSetting(t *testing.T) {
	var none *daemon
	if !none.urgentAlertsEnabled() {
		t.Error("with no settings store the alerts default to on")
	}
	d := &daemon{settings: newTestStore(t)}
	if !d.urgentAlertsEnabled() {
		t.Error("shipped default: urgent alerts on")
	}
	if err := d.settings.patch("urgentUpdates.enabled", rm("false")); err != nil {
		t.Fatal(err)
	}
	if d.urgentAlertsEnabled() {
		t.Error("urgentUpdates.enabled false turns the probe off")
	}
	if got := newSettingsStore(d.settings.path).cur.UrgentUpdates.Enabled; got {
		t.Error("the switch did not survive a reload of shell.json")
	}
	if err := d.settings.patch("urgentUpdates.enabled", rm(`"no"`)); err == nil {
		t.Error("a non-boolean value is refused")
	}
}
