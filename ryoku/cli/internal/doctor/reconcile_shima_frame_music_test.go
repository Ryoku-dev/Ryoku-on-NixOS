package doctor

import (
	"encoding/json"
	"testing"
)

func TestStripShimaFrameMusicKey(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		changed bool
		wantErr bool
	}{
		{
			name:    "retires the stored wave choice and keeps every sibling",
			in:      `{"barStyle":"iris","inir":{"iris":{"surround":{"enable":true,"music":"widget","thickness":12,"radius":20,"musicEdges":"all"},"bar":{"position":"top"}},"background":{"edgeWidgets":{"organic":{"enable":true}}}},"custom":{"nested":[1,2,3]}}`,
			changed: true,
		},
		{
			name:    "retires the stored frame choice too",
			in:      `{"inir":{"iris":{"surround":{"enable":true,"music":"frame"}}}}`,
			changed: true,
		},
		{name: "store without the key is unchanged", in: `{"inir":{"iris":{"surround":{"enable":true,"thickness":10}}}}`, changed: false},
		{name: "store without a surround object is unchanged", in: `{"inir":{"iris":{"bar":{"position":"top"}}}}`, changed: false},
		{name: "store without an inir tree is unchanged", in: `{"barStyle":"qsbar"}`, changed: false},
		{name: "invalid json errors", in: `not json`, wantErr: true},
		{name: "null top level errors", in: `null`, wantErr: true},
		{name: "malformed inir errors", in: `{"inir":"not-an-object"}`, wantErr: true},
		{name: "malformed surround errors", in: `{"inir":{"iris":{"surround":"not-an-object"}}}`, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			out, changed, err := stripShimaFrameMusicKey([]byte(tt.in))
			if tt.wantErr {
				if err == nil {
					t.Fatal("migration succeeded, want error")
				}
				return
			}
			if err != nil {
				t.Fatalf("migration failed: %v", err)
			}
			if changed != tt.changed {
				t.Fatalf("changed = %v, want %v", changed, tt.changed)
			}
			if !changed {
				if out != nil {
					t.Fatalf("no-op migration returned output: %s", out)
				}
				return
			}

			var before, after map[string]any
			if err := json.Unmarshal([]byte(tt.in), &before); err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(out, &after); err != nil {
				t.Fatalf("migrated JSON does not parse: %v", err)
			}
			surround := after["inir"].(map[string]any)["iris"].(map[string]any)["surround"].(map[string]any)
			if _, present := surround["music"]; present {
				t.Fatal("retired music key survived")
			}
			beforeSurround := before["inir"].(map[string]any)["iris"].(map[string]any)["surround"].(map[string]any)
			delete(beforeSurround, "music")
			got, _ := json.Marshal(surround)
			want, _ := json.Marshal(beforeSurround)
			if string(got) != string(want) {
				t.Fatalf("surround siblings changed: before=%s after=%s", want, got)
			}
			for _, key := range []string{"barStyle", "custom"} {
				if before[key] == nil {
					continue
				}
				got, _ := json.Marshal(after[key])
				want, _ := json.Marshal(before[key])
				if string(got) != string(want) {
					t.Fatalf("unrelated %s changed: before=%s after=%s", key, want, got)
				}
			}
			if second, changed, err := stripShimaFrameMusicKey(out); err != nil || changed || second != nil {
				t.Fatalf("second migration must be a no-op: changed=%v out=%s err=%v", changed, second, err)
			}
		})
	}
}
