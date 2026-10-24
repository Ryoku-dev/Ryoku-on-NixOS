package doctor

import (
	"encoding/json"
	"testing"
)

// The strip drops the skwd bar's style, orientation and offsets, keeps the filter bar
// keys the masthead still reads, drops a filterBar it leaves empty, and no-ops once clean.
func TestStripRetiredFilterBarKeys(t *testing.T) {
	full := []byte(`{"filterBar":{"visualStyle":"slices","orientation":"vertical","offsetX":12,"offsetY":-4,"sticky":true,"show":{"colors":false}},"general":{"uiScale":1}}`)
	out, changed, err := stripRetiredFilterBarKeys(full)
	if err != nil || !changed {
		t.Fatalf("retired keys must be stripped: changed=%v err=%v", changed, err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(out, &cfg); err != nil {
		t.Fatalf("stripped JSON does not parse: %v", err)
	}
	bar, ok := cfg["filterBar"].(map[string]any)
	if !ok {
		t.Fatalf("filterBar with live keys was lost: %v", cfg)
	}
	for _, retired := range []string{"visualStyle", "orientation", "offsetX", "offsetY"} {
		if _, present := bar[retired]; present {
			t.Errorf("fix did not strip filterBar.%s", retired)
		}
	}
	for _, kept := range []string{"sticky", "show"} {
		if _, present := bar[kept]; !present {
			t.Errorf("live key filterBar.%s was lost: %v", kept, bar)
		}
	}
	if _, present := cfg["general"]; !present {
		t.Errorf("passthrough key general was lost: %v", cfg)
	}

	if _, changed, err := stripRetiredFilterBarKeys(out); err != nil || changed {
		t.Errorf("re-stripping a clean store must be a no-op: changed=%v err=%v", changed, err)
	}

	out, changed, err = stripRetiredFilterBarKeys([]byte(`{"filterBar":{"visualStyle":"hex"}}`))
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	var only map[string]any
	if err := json.Unmarshal(out, &only); err != nil {
		t.Fatalf("stripped JSON does not parse: %v", err)
	}
	if _, present := only["filterBar"]; present {
		t.Errorf("a filterBar left empty after the strip must be dropped, got %v", only["filterBar"])
	}

	if _, changed, err := stripRetiredFilterBarKeys([]byte(`{"paper":{}}`)); err != nil || changed {
		t.Errorf("a store with no filterBar must be untouched: changed=%v err=%v", changed, err)
	}
}
