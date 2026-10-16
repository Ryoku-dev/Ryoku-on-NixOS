package main

import (
	"os"
	"path/filepath"
	"testing"
)

// The ledger records a name once, so repeated switching never pads the file,
// and a name already there from the installer is left where it is.
func TestRecordProvisionedWritesEachNameOnce(t *testing.T) {
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	ledger := filepath.Join(state, "ryoku", "provisioned")
	if err := os.MkdirAll(filepath.Dir(ledger), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(ledger, []byte("yazi\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	for range 3 {
		if err := recordProvisioned("ryoku-rashin"); err != nil {
			t.Fatal(err)
		}
	}
	got, err := os.ReadFile(ledger)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "yazi\nryoku-rashin\n" {
		t.Fatalf("ledger = %q", got)
	}
}

func TestRecordProvisionedCreatesTheLedger(t *testing.T) {
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	if err := recordProvisioned("ryoku-rashin"); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(state, "ryoku", "provisioned"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "ryoku-rashin\n" {
		t.Fatalf("ledger = %q", got)
	}
}
