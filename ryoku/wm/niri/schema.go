package main

import (
	"embed"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed schema*.json
var schemaFS embed.FS

// runSchema prints niri's exclusive settings rows, in the shape the Hub's
// settings renderer already consumes. The rows live in topical files
// (schema.json plus schema_layout.json, schema_input.json, schema_anim.json,
// schema_rules.json), one concern each; this concatenates them into the single
// rows array the Hub expects, so niri's exclusives surface without a Hub edit,
// the same way a third compositor's would. Each row carries its own page tag,
// so window-manager rows land on the shared window-manager page while the
// animation, layer-rule and window-rule rows reach their bespoke pages.
func runSchema() error {
	rows, err := loadSchemaRows()
	if err != nil {
		return err
	}
	rows = withInstalledProfiles(rows)
	enc := json.NewEncoder(stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(rows)
}

// The key-sounds profile row offers what is installed, not only the names written
// in the schema: a pack a user imports with ryoku-keysounds-import has to be
// selectable without a schema edit. The shipped names stay first and are the
// whole list when the profiles package is absent.
const profileRowKey = "wm.niri.keysounds.profile"

func withInstalledProfiles(rows []json.RawMessage) []json.RawMessage {
	for i, raw := range rows {
		var row map[string]json.RawMessage
		if json.Unmarshal(raw, &row) != nil {
			continue
		}
		var key string
		if json.Unmarshal(row["key"], &key) != nil || key != profileRowKey {
			continue
		}
		var opts []string
		if json.Unmarshal(row["opts"], &opts) != nil {
			continue
		}
		if b, err := json.Marshal(appendMissing(opts, installedProfiles())); err == nil {
			row["opts"] = b
		}
		if b, err := json.Marshal(row); err == nil {
			rows[i] = b
		}
	}
	return rows
}

// installedProfiles lists the profile directories under the engine's two roots:
// the user's data dir and the package's.
func installedProfiles() []string {
	roots := []string{
		filepath.Join(dataHome(), "ryoku", "keysounds"),
		"/usr/share/ryoku/keysounds",
	}
	names := []string{}
	for _, root := range roots {
		entries, err := os.ReadDir(root)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() {
				names = append(names, e.Name())
			}
		}
	}
	sort.Strings(names)
	return names
}

func appendMissing(base, extra []string) []string {
	seen := make(map[string]bool, len(base))
	for _, s := range base {
		seen[s] = true
	}
	for _, s := range extra {
		if !seen[s] {
			seen[s] = true
			base = append(base, s)
		}
	}
	return base
}

// loadSchemaRows reads every embedded schema*.json array and concatenates them in
// a stable filename order, so the row set is deterministic across builds.
func loadSchemaRows() ([]json.RawMessage, error) {
	entries, err := schemaFS.ReadDir(".")
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		n := e.Name()
		if strings.HasPrefix(n, "schema") && strings.HasSuffix(n, ".json") {
			names = append(names, n)
		}
	}
	sort.Strings(names)

	rows := []json.RawMessage{}
	for _, n := range names {
		b, err := schemaFS.ReadFile(n)
		if err != nil {
			return nil, err
		}
		var arr []json.RawMessage
		if err := json.Unmarshal(b, &arr); err != nil {
			return nil, err
		}
		rows = append(rows, arr...)
	}
	return rows, nil
}
