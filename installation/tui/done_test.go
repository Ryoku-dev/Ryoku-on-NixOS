package main

import (
	"os/exec"
	"strings"
	"testing"
)

// The done screen used to just quit; now Enter must record the chosen action so
// main() can run it. q still exits to a shell without acting.
func TestDoneExitAction(t *testing.T) {
	for _, c := range []struct {
		sel  int
		want string
	}{{0, "reboot"}, {1, "poweroff"}, {2, "shell"}} {
		m := model{state: "done", doneSel: c.sel}
		nm, cmd := m.onKey("enter")
		if cmd == nil {
			t.Fatalf("doneSel %d: enter did not return a quit command", c.sel)
		}
		if got := nm.(model).exitAction; got != c.want {
			t.Fatalf("doneSel %d -> exitAction %q, want %q", c.sel, got, c.want)
		}
	}
	m := model{state: "done", doneSel: 0}
	nm, _ := m.onKey("q")
	if got := nm.(model).exitAction; got != "" {
		t.Fatalf("q set exitAction %q, want empty (no reboot/poweroff)", got)
	}
}

// Reboot now failed silently on the Void ISO: systemctl does not exist under
// runit. The plain commands exist under both init systems.
func TestApplyExitRunsCommandsEveryLiveMediumShips(t *testing.T) {
	var ran []string
	exitCommand = func(name string, args ...string) *exec.Cmd {
		ran = append(ran, strings.Join(append([]string{name}, args...), " "))
		return exec.Command("true")
	}
	t.Cleanup(func() { exitCommand = exec.Command })
	for _, action := range []string{"reboot", "poweroff", "shell", ""} {
		applyExit(action)
	}
	if got := strings.Join(ran, ", "); got != "reboot, poweroff" {
		t.Fatalf("exit commands = %q, want %q", got, "reboot, poweroff")
	}
}
