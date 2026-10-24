package doctor

import (
	"encoding/json"
	"testing"
)

func TestStripIrisBatteryThresholds(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		changed bool
		wantErr bool
	}{
		{
			name:    "retires both thresholds and keeps battery siblings",
			in:      `{"barStyle":"iris","inir":{"battery":{"low":20,"critical":5,"suspend":3,"automaticSuspend":true,"chargeLimit":{"enable":true,"threshold":80}},"iris":{"bar":{"position":"top"}}},"custom":{"nested":[1,2,3]}}`,
			changed: true,
		},
		{name: "retires one remaining threshold", in: `{"inir":{"battery":{"low":15,"suspend":4}}}`, changed: true},
		{name: "store without thresholds is unchanged", in: `{"inir":{"battery":{"suspend":3}}}`, changed: false},
		{name: "store without battery object is unchanged", in: `{"inir":{"iris":{"bar":{"position":"top"}}}}`, changed: false},
		{name: "store without inir tree is unchanged", in: `{"barStyle":"qsbar"}`, changed: false},
		{name: "invalid json errors", in: `not json`, wantErr: true},
		{name: "null top level errors", in: `null`, wantErr: true},
		{name: "malformed inir errors", in: `{"inir":"not-an-object"}`, wantErr: true},
		{name: "malformed battery errors", in: `{"inir":{"battery":"not-an-object"}}`, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			out, changed, err := stripIrisBatteryThresholds([]byte(tt.in))
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
			battery := after["inir"].(map[string]any)["battery"].(map[string]any)
			if _, present := battery["low"]; present {
				t.Fatal("retired low threshold survived")
			}
			if _, present := battery["critical"]; present {
				t.Fatal("retired critical threshold survived")
			}
			beforeBattery := before["inir"].(map[string]any)["battery"].(map[string]any)
			delete(beforeBattery, "low")
			delete(beforeBattery, "critical")
			got, _ := json.Marshal(battery)
			want, _ := json.Marshal(beforeBattery)
			if string(got) != string(want) {
				t.Fatalf("battery siblings changed: before=%s after=%s", want, got)
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
			if second, changed, err := stripIrisBatteryThresholds(out); err != nil || changed || second != nil {
				t.Fatalf("second migration must be a no-op: changed=%v out=%s err=%v", changed, second, err)
			}
		})
	}
}
