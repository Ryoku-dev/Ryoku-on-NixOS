package main

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestConcurrentConfigUpdatesPreserveEveryField(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	state := t.TempDir()
	t.Setenv("RYOKU_STATE_PATH", state)
	intro := "/tmp/rashin-intro"
	updates := []func(*Config){
		func(cfg *Config) { cfg.Enabled = false },
		func(cfg *Config) { cfg.OptedOut = true },
		func(cfg *Config) { cfg.Approvals = approvalsAuto },
		func(cfg *Config) { cfg.ChatAgent = "codex" },
		func(cfg *Config) { cfg.Quick.Route = "auto:fast" },
		func(cfg *Config) { cfg.AddProwlHarness("omp") },
		func(cfg *Config) { cfg.Intro = &intro },
	}
	start := make(chan struct{})
	errs := make(chan error, len(updates))
	var wg sync.WaitGroup
	for _, mutate := range updates {
		mutate := mutate
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			errs <- updateConfig(func(cfg *Config) error {
				mutate(cfg)
				return nil
			})
		}()
	}
	close(start)
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	got := LoadConfig()
	if got.Enabled || !got.OptedOut || got.Approvals != approvalsAuto || got.ChatAgent != "codex" ||
		got.Quick.Route != "auto:fast" || !got.HasProwlHarness("omp") || got.Intro == nil || *got.Intro != intro {
		t.Fatalf("concurrent updates were lost: %+v", got)
	}
	wantLock := filepath.Join(state, "rashin-config.lock")
	if gotPath := configLockPath(); gotPath != wantLock {
		t.Fatalf("config lock path = %q, want %q", gotPath, wantLock)
	}
	lockInfo, err := os.Stat(wantLock)
	if err != nil {
		t.Fatalf("state lock missing: %v", err)
	}
	if lockInfo.Mode().Perm() != 0o600 {
		t.Fatalf("state lock mode = %o", lockInfo.Mode().Perm())
	}
	if _, err := os.Stat(ConfigPath() + ".lock"); !os.IsNotExist(err) {
		t.Fatalf("config-directory lock should not exist: %v", err)
	}
}

func TestConfigLockPathUsesXDGStateHome(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("RYOKU_STATE_PATH", "")
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	want := filepath.Join(state, "ryoku", "rashin-config.lock")
	if got := configLockPath(); got != want {
		t.Fatalf("config lock path = %q, want %q", got, want)
	}
}
