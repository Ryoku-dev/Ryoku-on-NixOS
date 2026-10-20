package main

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// updates.go runs the background update check the Hub's Updates section and the
// bar's update glyph read, so a check happens whether or not the Hub is open.
// It polls `ryoku status --json` on the configured cadence (hub.toml
// update_interval), publishes the frame on the "updates" topic, and caches it.
// Between those checks it asks `ryoku status --urgent` every hour and runs a
// full check as soon as the channel serves an urgent commit the last frame did
// not list, so the shell's alert (services/UrgentUpdates.qml) does not wait for
// the next daily check.
type updatesState struct {
	topic  *stateTopic
	wake   chan struct{}
	quit   chan struct{}
	alerts func() bool
	// urgent holds the commits the last published frame listed as urgent.
	urgent map[string]bool
}

// urgentUpdatesSettings is shell.json's `urgentUpdates`: whether the shell
// raises the urgent-update alert and the daemon probes for one.
type urgentUpdatesSettings struct {
	Enabled bool `json:"enabled"`
}

// urgentProbeEvery is how often the daemon looks for an urgent commit between
// full checks. A probe costs one small fetch, plus one GitHub compare only when
// the channel has moved since the last.
const urgentProbeEvery = time.Hour

// ryokuStatus runs `ryoku status` with args. A var so tests stand in for it.
var ryokuStatus = func(args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	return exec.CommandContext(ctx, "ryoku", append([]string{"status"}, args...)...).Output()
}

func (d *daemon) startUpdates() {
	s := &updatesState{
		topic:  d.registerTopic("updates"),
		wake:   make(chan struct{}, 1),
		quit:   d.quit,
		alerts: d.urgentAlertsEnabled,
	}
	d.registerCall("updates.check", func(json.RawMessage) (any, error) {
		select {
		case s.wake <- struct{}{}:
		default:
		}
		return map[string]any{"ok": true}, nil
	})
	go s.run()
}

func (d *daemon) urgentAlertsEnabled() bool {
	if d == nil || d.settings == nil {
		return true
	}
	d.settings.mu.Lock()
	defer d.settings.mu.Unlock()
	if d.settings.cur == nil {
		return true
	}
	return d.settings.cur.UrgentUpdates.Enabled
}

// run checks once at startup for a login baseline, then on the interval or a
// forced wake, with urgent probes in between. "off" disables both, but still
// answers a manual check.
func (s *updatesState) run() {
	s.check()
	last := time.Now()
	for {
		wait, probe := nextUpdateWake(time.Since(last), updateCheckInterval(), s.alerts())
		if wait < 0 {
			select {
			case <-s.quit:
				return
			case <-s.wake:
				s.check()
				last = time.Now()
			}
			continue
		}
		t := time.NewTimer(wait)
		select {
		case <-s.quit:
			t.Stop()
			return
		case <-s.wake:
			t.Stop()
		case <-t.C:
			if probe && !s.urgentNews() {
				continue
			}
		}
		s.check()
		last = time.Now()
	}
}

// nextUpdateWake says how long to sleep once `since` has passed since the last
// full check, and whether that wake is an urgent probe rather than the check.
// A negative wait means periodic checks are off.
func nextUpdateWake(since, full time.Duration, alerts bool) (time.Duration, bool) {
	if full <= 0 {
		return -1, false
	}
	remaining := max(full-since, 0)
	if alerts && urgentProbeEvery < remaining {
		return urgentProbeEvery, true
	}
	return remaining, false
}

func (s *updatesState) check() {
	out, err := ryokuStatus("--json")
	if err != nil || len(out) == 0 {
		return
	}
	s.urgent = urgentSet(out)
	writeUpdateCache(out)
	s.topic.publish(out)
}

// urgentNews asks the probe whether the channel now serves an urgent commit the
// last frame did not list. A failed probe is no news.
func (s *updatesState) urgentNews() bool {
	out, err := ryokuStatus("--urgent", "--json")
	if err != nil {
		return false
	}
	for commit := range urgentSet(out) {
		if !s.urgent[commit] {
			return true
		}
	}
	return false
}

// urgentSet reads the commits a status frame lists under "urgent".
func urgentSet(frame []byte) map[string]bool {
	var f struct {
		Urgent []struct {
			Commit string `json:"commit"`
		} `json:"urgent"`
	}
	set := map[string]bool{}
	if json.Unmarshal(frame, &f) != nil {
		return set
	}
	for _, u := range f.Urgent {
		if u.Commit != "" {
			set[u.Commit] = true
		}
	}
	return set
}

func updateCheckInterval() time.Duration {
	switch readUpdateInterval() {
	case "off":
		return 0
	case "hourly":
		return time.Hour
	case "weekly":
		return 7 * 24 * time.Hour
	default:
		return 24 * time.Hour
	}
}

func readUpdateInterval() string {
	b, err := os.ReadFile(hubConfigPath())
	if err != nil {
		return "daily"
	}
	for _, ln := range strings.Split(string(b), "\n") {
		if !strings.Contains(ln, "update_interval") {
			continue
		}
		if i := strings.IndexByte(ln, '"'); i >= 0 {
			if j := strings.IndexByte(ln[i+1:], '"'); j >= 0 {
				return ln[i+1 : i+1+j]
			}
		}
	}
	return "daily"
}

func hubConfigPath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "hub.toml")
}

func writeUpdateCache(b []byte) {
	dir := filepath.Join(matugenCacheHome(), "ryoku")
	if os.MkdirAll(dir, 0o755) != nil {
		return
	}
	tmp := filepath.Join(dir, "update-status.json.tmp")
	if os.WriteFile(tmp, b, 0o644) == nil {
		_ = os.Rename(tmp, filepath.Join(dir, "update-status.json"))
	}
}
