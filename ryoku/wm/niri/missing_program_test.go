package main

import (
	"os"
	"strings"
	"testing"
)

// Every test in this package renders against a box that has every optional
// program, so a runner without Rashin cannot change what the fixtures expect.
func TestMain(m *testing.M) {
	hasProgram = func(string) bool { return true }
	os.Exit(m.Run())
}

func withoutProgram(t *testing.T, name string) {
	t.Helper()
	prev := hasProgram
	hasProgram = func(p string) bool { return p != name }
	t.Cleanup(func() { hasProgram = prev })
}

// With Rashin absent the Ask chord is not emitted, a rebind the user recorded
// for it does not resurrect it, the legend row keeps its place and names the
// program, and the window bind, whose program is present, stays bound.
func TestAbsentProgramDropsItsBind(t *testing.T) {
	withoutProgram(t, "ryoku-rashin")
	s := loadStore("")
	s.KeybindRebinds = map[string]string{"ALT + Space": "SUPER + CTRL + SHIFT + F12"}
	kdl, report := genBinds(s)
	for _, chord := range []string{"Alt+Space", "Super+Ctrl+Shift+F12"} {
		if strings.Contains(kdl, "\n    "+chord+" {") {
			t.Fatalf("%s is bound without ryoku-rashin:\n%s", chord, kdl)
		}
	}
	if !strings.Contains(kdl, "\n    Super+Alt+Space {") {
		t.Fatalf("the Rashin window bind went missing although rashin-app is present:\n%s", kdl)
	}
	reported := false
	for _, u := range report {
		if strings.Contains(u.Key, "ALT + Space") && u.Reason == "ryoku-rashin is not installed." {
			reported = true
		}
	}
	if !reported {
		t.Fatalf("apply did not report the dropped Ask bind: %+v", report)
	}
	for _, r := range bindRows(s) {
		if r.ID == "shell.ask" {
			if r.Unhonored != "ryoku-rashin is not installed." {
				t.Fatalf("shell.ask row reason = %q", r.Unhonored)
			}
			return
		}
	}
	t.Fatal("shell.ask row vanished from the legend")
}

func TestPresentProgramKeepsAsk(t *testing.T) {
	kdl, _ := genBinds(loadStore(""))
	if !strings.Contains(kdl, "\n    Alt+Space {") {
		t.Fatalf("Ask is unbound with ryoku-rashin present:\n%s", kdl)
	}
}
