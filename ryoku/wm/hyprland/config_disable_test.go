package main

import (
	"strings"
	"testing"
)

// A moved bind that is switched off must not be registered at either chord or
// released after another bind has had a chance to claim its old chord.
func TestDisabledMovedBindIsNeverRegisteredOrUnbound(t *testing.T) {
	o := Overrides{
		KeybindRebinds:  map[string]string{"SUPER + W": "SUPER + ALT + W"},
		KeybindDisabled: []string{"SUPER + W"},
	}
	got := string(renderRebinds(o))
	if !strings.Contains(got, `["SUPER + W"] = false`) {
		t.Fatalf("disabled lookup missing:\n%s", got)
	}
	if strings.Contains(got, `"SUPER + ALT + W"`) {
		t.Errorf("disabled bind still registers its moved chord:\n%s", got)
	}
	if got := genUnbinds(o); got != "" {
		t.Errorf("disabled bind is released after registration:\n%s", got)
	}
}

// A disabled family overrides both its family rebind and a legacy per-member
// rebind, including every NumLock-off key that binds.lua looks up.
func TestDisabledFamilyOverridesLegacyMemberRebind(t *testing.T) {
	o := Overrides{
		KeybindRebinds: map[string]string{
			"SUPER + KP_{n}": "SUPER + CTRL + KP_{n}",
			"SUPER + KP_3":   "SUPER + ALT + KP_3",
		},
		KeybindDisabled: []string{"SUPER + KP_{n}"},
	}
	got := string(renderRebinds(o))
	for _, chord := range []string{"SUPER + KP_1", "SUPER + KP_3", "SUPER + KP_0", "SUPER + KP_End"} {
		want := `["` + chord + `"] = false`
		if !strings.Contains(got, want) {
			t.Errorf("missing %s in:\n%s", want, got)
		}
		if n := strings.Count(got, `["`+chord+`"]`); n != 1 {
			t.Errorf("%s emitted %d times, want 1:\n%s", chord, n, got)
		}
	}
	for _, moved := range []string{"SUPER + CTRL + KP_1", "SUPER + ALT + KP_3"} {
		if strings.Contains(got, moved) {
			t.Errorf("disabled family still registers %s:\n%s", moved, got)
		}
	}
}

// A provider-exclusive bind has no catalogue family but still uses its shipped
// chord as the stable key in the disabled list.
func TestDisabledExclusiveBindIsNotRegistered(t *testing.T) {
	got := string(renderRebinds(Overrides{KeybindDisabled: []string{"SUPER + ALT + X"}}))
	if !strings.Contains(got, `["SUPER + ALT + X"] = false`) {
		t.Fatalf("exclusive disabled lookup missing:\n%s", got)
	}
}
