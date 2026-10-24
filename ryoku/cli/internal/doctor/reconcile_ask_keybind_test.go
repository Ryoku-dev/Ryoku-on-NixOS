package doctor

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
	"testing"
)

func TestMigrateAskKeybind(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		changed bool
		wantErr bool
	}{
		{
			name:    "drops only the retired chord",
			in:      `{"desktop":{"keybindRebinds":{"SUPER + S":"SUPER + X","SUPER + K":"SUPER + slash"},"keybinds":[{"keys":"ALT + K","action":"exec","value":"kitty"}]},"theme":"paper","custom":{"nested":[1,2,3]}}`,
			changed: true,
		},
		{
			name: "current rebinds are unchanged",
			in:   `{"desktop":{"keybindRebinds":{"SUPER + K":"SUPER + slash"}},"theme":"paper"}`,
		},
		{
			name: "missing desktop is unchanged",
			in:   `{"theme":"paper"}`,
		},
		{name: "invalid json errors", in: `not json`, wantErr: true},
		{name: "null top level errors", in: `null`, wantErr: true},
		{name: "malformed desktop errors", in: `{"desktop":"bad"}`, wantErr: true},
		{name: "malformed rebinds error", in: `{"desktop":{"keybindRebinds":[]}}`, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			out, changed, err := migrateAskKeybind([]byte(tt.in))
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

			var before, after map[string]json.RawMessage
			if err := json.Unmarshal([]byte(tt.in), &before); err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(out, &after); err != nil {
				t.Fatalf("migrated JSON does not parse: %v", err)
			}
			for _, key := range []string{"theme", "custom"} {
				if !sameJSON(after[key], before[key]) {
					t.Fatalf("top-level %s changed: before=%s after=%s", key, before[key], after[key])
				}
			}

			var beforeDesktop, afterDesktop map[string]json.RawMessage
			if err := json.Unmarshal(before["desktop"], &beforeDesktop); err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(after["desktop"], &afterDesktop); err != nil {
				t.Fatal(err)
			}
			if !sameJSON(afterDesktop["keybinds"], beforeDesktop["keybinds"]) {
				t.Fatalf("custom keybinds changed: before=%s after=%s", beforeDesktop["keybinds"], afterDesktop["keybinds"])
			}
			var rebinds map[string]string
			if err := json.Unmarshal(afterDesktop["keybindRebinds"], &rebinds); err != nil {
				t.Fatal(err)
			}
			if _, present := rebinds["SUPER + S"]; present {
				t.Fatal("retired SUPER + S rebind survived")
			}
			if rebinds["SUPER + K"] != "SUPER + slash" {
				t.Fatalf("sibling rebind changed: %v", rebinds)
			}
		})
	}
}

func TestReconcileAskKeybind(t *testing.T) {
	tests := []struct {
		name      string
		contents  *string
		checkOnly bool
		want      recStatus
		wantSame  bool
	}{
		{name: "missing file", want: recOK},
		{name: "no-op", contents: stringPtr(`{"desktop":{"keybindRebinds":{"SUPER + K":"SUPER + slash"}}}`), want: recOK, wantSame: true},
		{name: "check-only", contents: stringPtr(`{"desktop":{"keybindRebinds":{"SUPER + S":"SUPER + X"}},"theme":"paper"}`), checkOnly: true, want: recWouldFix, wantSame: true},
		{name: "changed", contents: stringPtr(`{"desktop":{"keybindRebinds":{"SUPER + S":"SUPER + X","SUPER + K":"SUPER + slash"}},"theme":"paper"}`), want: recFixed},
		{name: "parse error", contents: stringPtr(`not json`), want: recWarn, wantSame: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			home := t.TempDir()
			t.Setenv("HOME", home)
			t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
			path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
			if tt.contents != nil {
				if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(*tt.contents), 0o644); err != nil {
					t.Fatal(err)
				}
			}

			r := reconcileAskKeybind(tt.checkOnly)
			if r.status != tt.want {
				t.Fatalf("status=%s detail=%q, want %s", r.status.label(), r.detail, tt.want.label())
			}
			if tt.contents == nil {
				if _, err := os.Stat(path); !os.IsNotExist(err) {
					t.Fatalf("missing file was created: %v", err)
				}
				return
			}
			got, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if tt.wantSame && string(got) != *tt.contents {
				t.Fatalf("file changed: got=%q want=%q", got, *tt.contents)
			}
			if tt.want == recFixed {
				var cfg struct {
					Desktop struct {
						KeybindRebinds map[string]string `json:"keybindRebinds"`
					} `json:"desktop"`
					Theme string `json:"theme"`
				}
				if err := json.Unmarshal(got, &cfg); err != nil {
					t.Fatal(err)
				}
				if _, present := cfg.Desktop.KeybindRebinds["SUPER + S"]; present {
					t.Fatal("fix left the retired rebind in place")
				}
				if cfg.Desktop.KeybindRebinds["SUPER + K"] != "SUPER + slash" || cfg.Theme != "paper" {
					t.Fatalf("fix changed siblings: %+v", cfg)
				}
			}
		})
	}
}

func stringPtr(s string) *string { return &s }

// sameJSON compares two documents by value; re-indenting on write is not a change.
func sameJSON(a, b json.RawMessage) bool {
	var left, right bytes.Buffer
	if json.Compact(&left, a) != nil || json.Compact(&right, b) != nil {
		return false
	}
	return left.String() == right.String()
}
