package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestKeyboardEnumerationUsesPackagedRulesDirectory(t *testing.T) {
	rules := t.TempDir()
	body := `! layout
  us          English (US)
  gb          English (UK)
  is          Icelandic
! variant
  intl        us: English (US, intl.)
  extd        gb: English (UK, extended)
  nodeadkeys  is: Icelandic (no dead keys)
`
	if err := os.WriteFile(filepath.Join(rules, "base.lst"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_XKB_RULES_DIR", rules)
	t.Setenv("XKB_CONFIG_ROOT", "")

	layouts := listKbLayouts()
	if len(layouts) != 3 {
		t.Fatalf("layouts = %#v, want all 3 packaged layouts", layouts)
	}
	if got := layouts[2]["code"]; got != "is" {
		t.Fatalf("third layout = %q, want is", got)
	}

	variants := listKbVariants("gb")
	if len(variants) != 1 || variants[0]["code"] != "extd" {
		t.Fatalf("gb variants = %#v, want extd from packaged rules", variants)
	}
}
