package main

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"
)

func writeSupply(t *testing.T, root, name string, fields map[string]string) {
	t.Helper()
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	for k, v := range fields {
		if err := os.WriteFile(filepath.Join(dir, k), []byte(v+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestPowerEventOverflowReconcilesAndKeepsReading(t *testing.T) {
	stop := errors.New("stop")
	reads := 0
	changes := 0
	err := runPowerEventReader(func([]byte) (int, error) {
		reads++
		if reads == 1 {
			return 0, syscall.ENOBUFS
		}
		return 0, stop
	}, func() {
		changes++
	})
	if err != stop {
		t.Fatalf("watcher returned %v, want sentinel", err)
	}
	if reads != 2 || changes != 1 {
		t.Fatalf("reads=%d changes=%d, want 2 reads and 1 reconcile", reads, changes)
	}
}

func TestParsePowerState(t *testing.T) {
	t.Run("discharging laptop, peripheral ignored", func(t *testing.T) {
		root := t.TempDir()
		writeSupply(t, root, "BAT0", map[string]string{"type": "Battery", "status": "Discharging", "capacity": "42"})
		writeSupply(t, root, "AC", map[string]string{"type": "Mains", "online": "0"})
		writeSupply(t, root, "hidpp_battery", map[string]string{"type": "Battery", "scope": "Device", "status": "Discharging", "capacity": "88"})
		on, present, pct, have := parsePowerState(root)
		if !on || !present || !have || pct != 42 {
			t.Fatalf("got on=%v present=%v pct=%d have=%v; want on present 42", on, present, pct, have)
		}
	})
	t.Run("plugged in, charging", func(t *testing.T) {
		root := t.TempDir()
		writeSupply(t, root, "BAT0", map[string]string{"type": "Battery", "status": "Full", "capacity": "100"})
		writeSupply(t, root, "AC", map[string]string{"type": "Mains", "online": "1"})
		on, present, _, _ := parsePowerState(root)
		if on || !present {
			t.Fatalf("charging laptop must not read on-battery: on=%v present=%v", on, present)
		}
	})
	t.Run("desktop, no battery", func(t *testing.T) {
		root := t.TempDir()
		writeSupply(t, root, "AC", map[string]string{"type": "Mains", "online": "1"})
		on, present, _, have := parsePowerState(root)
		if on || present || have {
			t.Fatalf("desktop must report external, no battery: on=%v present=%v have=%v", on, present, have)
		}
	})
	t.Run("missing tree", func(t *testing.T) {
		on, present, _, _ := parsePowerState(filepath.Join(t.TempDir(), "nope"))
		if on || present {
			t.Fatal("a missing power-supply tree must read as no battery")
		}
	})
}
