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
type updatesState struct {
	topic *stateTopic
	wake  chan struct{}
	quit  chan struct{}
}

func (d *daemon) startUpdates() {
	s := &updatesState{
		topic: d.registerTopic("updates"),
		wake:  make(chan struct{}, 1),
		quit:  d.quit,
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

// run checks once at startup for a login baseline, then on the interval or a
// forced wake. "off" disables the periodic tick but still answers a manual check.
func (s *updatesState) run() {
	s.check()
	for {
		d := updateCheckInterval()
		if d <= 0 {
			select {
			case <-s.quit:
				return
			case <-s.wake:
				s.check()
			}
			continue
		}
		t := time.NewTimer(d)
		select {
		case <-s.quit:
			t.Stop()
			return
		case <-s.wake:
			t.Stop()
			s.check()
		case <-t.C:
			s.check()
		}
	}
}

func (s *updatesState) check() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ryoku", "status", "--json").Output()
	if err != nil || len(out) == 0 {
		return
	}
	writeUpdateCache(out)
	s.topic.publish(out)
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
