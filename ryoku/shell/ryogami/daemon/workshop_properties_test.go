package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestMergePropertiesPrecedenceAndKinds(t *testing.T) {
	declared := map[string]interface{}{
		"tint":  map[string]interface{}{"type": "color", "value": "1 1 1", "text": "Tint", "order": float64(2)},
		"speed": map[string]interface{}{"type": "slider", "value": float64(5), "min": float64(0), "max": float64(10), "order": float64(1)},
		"flag":  map[string]interface{}{"value": true},
		"pick":  map[string]interface{}{"value": float64(1), "options": []interface{}{map[string]interface{}{"label": "A", "value": float64(0)}}},
	}
	overrides := map[string]interface{}{"tint": "0 0 0"}
	rows := mergeProperties(declared, overrides)
	if len(rows) != 4 {
		t.Fatalf("rows=%d", len(rows))
	}
	if rows[0].Name != "speed" {
		t.Fatalf("order sort: first=%s want speed", rows[0].Name)
	}
	byName := map[string]weProperty{}
	for _, r := range rows {
		byName[r.Name] = r
	}
	if s := byName["speed"]; s.Kind != weKindSlider || s.Min == nil || *s.Min != 0 || s.Max == nil || *s.Max != 10 {
		t.Fatalf("speed row wrong: %#v", s)
	}
	if tint := byName["tint"]; tint.Kind != weKindColor || tint.Value != "0 0 0" || !tint.Overridden || tint.Default != "1 1 1" {
		t.Fatalf("tint override wrong: %#v", tint)
	}
	if byName["flag"].Kind != weKindBool {
		t.Fatalf("flag kind=%s want bool", byName["flag"].Kind)
	}
	if byName["pick"].Kind != weKindCombo {
		t.Fatalf("pick kind=%s want combo", byName["pick"].Kind)
	}
}

func TestInferColorKind(t *testing.T) {
	entry := map[string]interface{}{"value": "0.5 0.2 0.1"}
	if got := resolveKind("", entry, entry["value"]); got != weKindColor {
		t.Fatalf("three-float string should infer color, got %s", got)
	}
	if got := resolveKind("mystery", entry, entry["value"]); got != weKindUnsupported {
		t.Fatalf("unknown declared type should be unsupported, got %s", got)
	}
}

func TestWePropStoreRoundTrip(t *testing.T) {
	d := &daemon{}
	d.cfg.Paths.Cache = t.TempDir()
	s := newWePropStore(d)

	s.setValue("100", "tint", "0 0 0")
	if got := s.overrides("100")["tint"]; got != "0 0 0" {
		t.Fatalf("override not persisted: %v", got)
	}
	if got := newWePropStore(d).overrides("100")["tint"]; got != "0 0 0" {
		t.Fatalf("override not durable: %v", got)
	}

	s.setFps("100", 120)
	if fps, ok := s.fpsOverride("100"); !ok || fps != 120 {
		t.Fatalf("fps override: %d %v", fps, ok)
	}

	s.resetValue("100", "tint")
	if _, ok := s.overrides("100")["tint"]; ok {
		t.Fatal("override not cleared")
	}
	if fps, ok := s.fpsOverride("100"); !ok || fps != 120 {
		t.Fatalf("fps lost after reset: %d %v", fps, ok)
	}
}

// TestSceneFpsFollowsGlobalUntilPinned: the panel shows "Default" only while a
// scene has no rate of its own, so fps is null until pinned, a null write
// unpins it, and Restore defaults clears the pin along with every property.
func TestSceneFpsFollowsGlobalUntilPinned(t *testing.T) {
	d := newSettingsDaemon(t)
	cache := t.TempDir()
	d.cfg.Paths.Cache = cache
	d.store = openStore(cache)
	d.workshop = newWorkshopLib(d)
	workshopRoot := t.TempDir()
	if err := d.persistSetting("paths.steamWorkshop", workshopRoot); err != nil {
		t.Fatal(err)
	}
	const id = "3100000001"
	dir := filepath.Join(workshopRoot, id)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	project := `{"type":"scene","title":"Harbour","general":{"properties":{
		"rain":{"order":1,"text":"Rain","type":"slider","min":0,"max":100,"value":40}}}}`
	if err := os.WriteFile(filepath.Join(dir, "project.json"), []byte(project), 0o644); err != nil {
		t.Fatal(err)
	}

	call := func(method, params string) map[string]interface{} {
		t.Helper()
		req := &request{Method: method, ID: 1, Params: json.RawMessage(params)}
		resp, _ := d.dispatchWorkshop(req, req.params())
		if resp.Error != nil {
			t.Fatalf("%s %s: %+v", method, params, resp.Error)
		}
		return resp.Result.(map[string]interface{})
	}
	fpsOf := func() interface{} { return call("workshop.properties", `{"weId":"`+id+`"}`)["fps"] }

	if got := fpsOf(); got != nil {
		t.Fatalf("fps before any pin = %v, want null so the panel shows Default", got)
	}
	call("workshop.setProperty", `{"weId":"`+id+`","fps":60}`)
	if got := fpsOf(); got != 60 {
		t.Fatalf("fps after pinning 60 = %v", got)
	}
	call("workshop.setProperty", `{"weId":"`+id+`","fps":null}`)
	if got := fpsOf(); got != nil {
		t.Fatalf("fps after a null write = %v, want null", got)
	}

	call("workshop.setProperty", `{"weId":"`+id+`","fps":24}`)
	call("workshop.setProperty", `{"weId":"`+id+`","name":"rain","value":90}`)
	res := call("workshop.setProperty", `{"weId":"`+id+`","reset":true}`)
	if res["fps"] != nil {
		t.Fatalf("fps after Restore defaults = %v, want null", res["fps"])
	}
	rows := res["properties"].([]weProperty)
	if len(rows) != 1 || rows[0].Overridden {
		t.Fatalf("rows after Restore defaults = %+v, want rain back at its default", rows)
	}
}
