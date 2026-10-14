package doctor

import (
	"encoding/json"
	"reflect"
	"testing"
)

func currentShellConfigForFrameKey(t *testing.T) map[string]any {
	t.Helper()
	out, changes, err := migrateShellConfig([]byte(`{}`))
	if err != nil || len(changes) == 0 {
		t.Fatalf("seed current shell config: changes=%v err=%v", changes, err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(out, &cfg); err != nil {
		t.Fatalf("decode current shell config: %v", err)
	}
	return cfg
}

func marshalShellFrameKeyConfig(t *testing.T, cfg map[string]any) []byte {
	t.Helper()
	raw, err := json.Marshal(cfg)
	if err != nil {
		t.Fatalf("encode shell config: %v", err)
	}
	return raw
}

func TestMigrateShellConfigRemovesRetiredFrameKey(t *testing.T) {
	cfg := currentShellConfigForFrameKey(t)
	cfg["top_level_sibling"] = "kept"
	frame := map[string]any{
		"enable_frame":   false,
		"monitor_filter": []any{"DP-1"},
		"frame_sibling":  map[string]any{"kept": true},
	}
	cfg["bars"] = map[string]any{
		"frame":       frame,
		"bar_sibling": map[string]any{"kept": true},
	}

	out, changes, err := migrateShellConfig(marshalShellFrameKeyConfig(t, cfg))
	if err != nil {
		t.Fatalf("migrate shell config: %v", err)
	}
	if len(changes) != 1 || changes[0] != "removed retired bars.frame.enable_frame setting" {
		t.Fatalf("changes = %v, want retired frame-key removal", changes)
	}
	delete(frame, "enable_frame")
	var got map[string]any
	if err := json.Unmarshal(out, &got); err != nil {
		t.Fatalf("decode migrated shell config: %v", err)
	}
	if !reflect.DeepEqual(got, cfg) {
		t.Fatalf("migration changed sibling settings:\n got: %#v\nwant: %#v", got, cfg)
	}

	if again, secondChanges, err := migrateShellConfig(out); err != nil || again != nil || secondChanges != nil {
		t.Fatalf("second migration must be idle: out=%s changes=%v err=%v", again, secondChanges, err)
	}
}

func TestMigrateShellConfigWithoutRetiredFrameKeyIsUntouched(t *testing.T) {
	cfg := currentShellConfigForFrameKey(t)
	cfg["bars"] = map[string]any{
		"frame":   map[string]any{"monitor_filter": []any{"DP-1"}},
		"widgets": map[string]any{"quick_settings": map[string]any{"icon": "Arch"}},
	}
	raw := marshalShellFrameKeyConfig(t, cfg)

	out, changes, err := migrateShellConfig(raw)
	if err != nil || out != nil || changes != nil {
		t.Fatalf("current shell config changed: out=%s changes=%v err=%v", out, changes, err)
	}
}

func TestMigrateShellConfigPrunesEmptyFrameObjects(t *testing.T) {
	cfg := currentShellConfigForFrameKey(t)
	cfg["bars"] = map[string]any{
		"frame": map[string]any{"enable_frame": true},
	}

	out, changes, err := migrateShellConfig(marshalShellFrameKeyConfig(t, cfg))
	if err != nil || len(changes) != 1 {
		t.Fatalf("migrate shell config: changes=%v err=%v", changes, err)
	}
	var got map[string]any
	if err := json.Unmarshal(out, &got); err != nil {
		t.Fatalf("decode migrated shell config: %v", err)
	}
	if _, present := got["bars"]; present {
		t.Fatalf("empty bars object survived migration: %#v", got["bars"])
	}
}
