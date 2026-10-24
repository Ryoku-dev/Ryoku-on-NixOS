package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// The sound-profile picker lists what is installed, so a profile a user imports
// with ryoku-keysounds-import can be chosen; the shipped names stay and nothing
// is listed twice.
func TestSchemaListInstalledProfiles(t *testing.T) {
	data := t.TempDir()
	t.Setenv("XDG_DATA_HOME", data)
	if err := os.MkdirAll(filepath.Join(data, "ryoku", "keysounds", "zz-imported"), 0o755); err != nil {
		t.Fatal(err)
	}

	rows, err := loadSchemaRows()
	if err != nil {
		t.Fatal(err)
	}
	opts := profileRowOpts(t, withInstalledProfiles(rows))

	want := []string{"zz-imported", "cherry-mx-brown"}
	for _, name := range want {
		if !contains(opts, name) {
			t.Errorf("profile %q missing from %v", name, opts)
		}
	}
	seen := map[string]bool{}
	for _, o := range opts {
		if seen[o] {
			t.Errorf("profile %q listed twice in %v", o, opts)
		}
		seen[o] = true
	}
}

func profileRowOpts(t *testing.T, rows []json.RawMessage) []string {
	t.Helper()
	for _, raw := range rows {
		var row struct {
			Key  string   `json:"key"`
			Opts []string `json:"opts"`
		}
		if err := json.Unmarshal(raw, &row); err != nil {
			t.Fatal(err)
		}
		if row.Key == profileRowKey {
			return row.Opts
		}
	}
	t.Fatalf("no %s row in the schema", profileRowKey)
	return nil
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}
