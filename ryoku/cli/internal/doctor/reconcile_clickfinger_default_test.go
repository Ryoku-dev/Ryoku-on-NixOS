package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestReconcileClickfingerFreshDefault(t *testing.T) {
	configRoot, stateRoot := clickfingerMigrationRoots(t)

	res := reconcileClickfingerDefault(false)
	if res.status != recOK {
		t.Fatalf("fresh config = %s (%s), want ok", res.status.label(), res.detail)
	}
	if _, err := os.Stat(filepath.Join(configRoot, "ryoku", "desktop.json")); !os.IsNotExist(err) {
		t.Fatalf("fresh config should use the shipped true default without a stored override: %v", err)
	}
	assertClickfingerMarker(t, stateRoot)
}

func TestReconcileClickfingerStoredFalseMigrates(t *testing.T) {
	configRoot, stateRoot := clickfingerMigrationRoots(t)
	path := writeClickfingerStore(t, configRoot, false)

	res := reconcileClickfingerDefault(false)
	if res.status != recFixed {
		t.Fatalf("stored false = %s (%s), want fixed", res.status.label(), res.detail)
	}
	assertStoredClickfinger(t, path, true)
	assertClickfingerMarker(t, stateRoot)

	var doc map[string]any
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	wm := doc["wm"].(map[string]any)
	if wm["alpha"].(map[string]any)["overviewZoom"] != 0.5 ||
		wm["beta"].(map[string]any)["layout"] != "dwindle" {
		t.Fatalf("provider-specific settings changed: %#v", wm)
	}
}

func TestReconcileClickfingerMarkedFalseStaysFalse(t *testing.T) {
	configRoot, stateRoot := clickfingerMigrationRoots(t)
	path := writeClickfingerStore(t, configRoot, false)
	marker := filepath.Join(stateRoot, "ryoku", "migrations", clickfingerDefaultMigration)
	if err := os.MkdirAll(filepath.Dir(marker), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(marker, []byte("done\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	res := reconcileClickfingerDefault(false)
	if res.status != recOK {
		t.Fatalf("marked false = %s (%s), want ok", res.status.label(), res.detail)
	}
	assertStoredClickfinger(t, path, false)
}

func TestReconcileClickfingerStoredTrueUntouched(t *testing.T) {
	configRoot, stateRoot := clickfingerMigrationRoots(t)
	path := writeClickfingerStore(t, configRoot, true)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	res := reconcileClickfingerDefault(false)
	if res.status != recOK {
		t.Fatalf("stored true = %s (%s), want ok", res.status.label(), res.detail)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatalf("stored true changed:\nbefore %s\nafter  %s", before, after)
	}
	assertClickfingerMarker(t, stateRoot)
}

func TestReconcileClickfingerCheckOnlyWritesNothing(t *testing.T) {
	configRoot, stateRoot := clickfingerMigrationRoots(t)
	path := writeClickfingerStore(t, configRoot, false)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	res := reconcileClickfingerDefault(true)
	if res.status != recWouldFix {
		t.Fatalf("check-only false = %s (%s), want todo", res.status.label(), res.detail)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatalf("check-only changed desktop.json:\nbefore %s\nafter  %s", before, after)
	}
	marker := filepath.Join(stateRoot, "ryoku", "migrations", clickfingerDefaultMigration)
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("check-only wrote the migration marker: %v", err)
	}
}

func clickfingerMigrationRoots(t *testing.T) (string, string) {
	t.Helper()
	configRoot := filepath.Join(t.TempDir(), "config")
	stateRoot := filepath.Join(t.TempDir(), "state")
	t.Setenv("XDG_CONFIG_HOME", configRoot)
	t.Setenv("XDG_STATE_HOME", stateRoot)
	return configRoot, stateRoot
}

func writeClickfingerStore(t *testing.T, configRoot string, value bool) string {
	t.Helper()
	dir := filepath.Join(configRoot, "ryoku")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	valueJSON := "false"
	if value {
		valueJSON = "true"
	}
	body := `{
  "desktop": {
    "input": {"clickfinger": ` + valueJSON + `, "tapToClick": true},
    "cursor": {"theme": "Bibata-Modern-Ice"}
  },
  "wm": {
    "alpha": {"overviewZoom": 0.5},
    "beta": {"layout": "dwindle"}
  }
}
`
	path := filepath.Join(dir, "desktop.json")
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func assertStoredClickfinger(t *testing.T, path string, want bool) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Desktop struct {
			Input struct {
				Clickfinger bool `json:"clickfinger"`
			} `json:"input"`
		} `json:"desktop"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	if doc.Desktop.Input.Clickfinger != want {
		t.Fatalf("desktop.input.clickfinger = %v, want %v", doc.Desktop.Input.Clickfinger, want)
	}
}

func assertClickfingerMarker(t *testing.T, stateRoot string) {
	t.Helper()
	marker := filepath.Join(stateRoot, "ryoku", "migrations", clickfingerDefaultMigration)
	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("clickfinger migration marker was not written: %v", err)
	}
}
