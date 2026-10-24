package doctor

import (
	"encoding/json"
	"testing"
)

// The strip drops the paper.awww object and every retired engine key (engine,
// videoEngine, wallpaperLayer, videoMultiProcess), keeps the scene-renderer keys
// (idlePauseSeconds, loadTimeoutSeconds, performanceMode), and no-ops once the
// retired keys are gone.
func TestStripRetiredPaperKeys(t *testing.T) {
	full := []byte(`{"paper":{"engine":"skwd-paper","videoEngine":"in_shell","wallpaperLayer":"top","videoMultiProcess":true,"awww":{"filter":"Lanczos3"},"idlePauseSeconds":60,"performanceMode":false},"general":{"uiScale":1}}`)
	out, changed, err := stripRetiredPaperKeys(full)
	if err != nil || !changed {
		t.Fatalf("retired keys must be stripped: changed=%v err=%v", changed, err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(out, &cfg); err != nil {
		t.Fatalf("stripped JSON does not parse: %v", err)
	}
	paper, ok := cfg["paper"].(map[string]any)
	if !ok {
		t.Fatalf("paper namespace lost: %v", cfg)
	}
	for _, retired := range []string{"engine", "videoEngine", "wallpaperLayer", "videoMultiProcess", "awww"} {
		if _, present := paper[retired]; present {
			t.Errorf("fix did not strip paper.%s", retired)
		}
	}
	for _, kept := range []string{"idlePauseSeconds", "performanceMode"} {
		if _, present := paper[kept]; !present {
			t.Errorf("live scene key paper.%s was lost: %v", kept, paper)
		}
	}
	if _, present := cfg["general"]; !present {
		t.Errorf("passthrough key general was lost: %v", cfg)
	}

	// stripping is idempotent: the cleaned store is now a no-op.
	if _, changed, err := stripRetiredPaperKeys(out); err != nil || changed {
		t.Errorf("re-stripping a clean store must be a no-op: changed=%v err=%v", changed, err)
	}

	// an awww engine value is stripped along with the rest.
	awww := []byte(`{"paper":{"engine":"awww","awww":{"transitionType":"wipe"}}}`)
	out, changed, err = stripRetiredPaperKeys(awww)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	var a map[string]any
	if err := json.Unmarshal(out, &a); err != nil {
		t.Fatalf("stripped JSON does not parse: %v", err)
	}
	if _, present := a["paper"]; present {
		t.Errorf("a paper left empty after the strip must be dropped, got %v", a["paper"])
	}

	// a store with no paper namespace is untouched.
	if _, changed, err := stripRetiredPaperKeys([]byte(`{"bars":{}}`)); err != nil || changed {
		t.Errorf("a store with no paper namespace must be untouched: changed=%v err=%v", changed, err)
	}
}
