package main

import "testing"

// esc must walk back out of text entry, including the multi-field administrator
// account screen. Text entry bypasses the global esc handler.
func TestEscGoesBackFromTextSteps(t *testing.T) {
	for _, key := range []string{"hostname", "administrator"} {
		m := model{state: "wizard", flow: steps(), picks: map[string]string{}}
		m.idx = flowIndex(m.flow, key)
		if m.idx <= 0 {
			t.Fatalf("step %q not reachable in flow", key)
		}
		m.loadStep()
		if key == "hostname" {
			m.input = "typed"
		} else {
			m.accounts.adminName = "typed"
		}
		before := m.idx
		nm, _ := m.onKey("esc")
		got := nm.(model)
		if got.idx >= before {
			t.Fatalf("%s: esc did not go back (idx %d -> %d)", key, before, got.idx)
		}
		if !got.stepActive(got.idx) {
			t.Fatalf("%s: esc landed on an inactive step (idx %d)", key, got.idx)
		}
	}
}

func TestEscFromLoginShellReturnsToBrowser(t *testing.T) {
	m := newModel()
	m.state = "wizard"
	m.idx = flowIndex(m.flow, "login-shell")
	m.loadStep()
	next, _ := m.onKey("esc")
	got := next.(model)
	if got.cur().key != "browser" {
		t.Fatalf("esc from login-shell landed on %q, want browser", got.cur().key)
	}
}

// a printable key on a text step must still edit the field, not navigate.
func TestInputStepStillTypes(t *testing.T) {
	m := model{state: "wizard", flow: steps(), picks: map[string]string{}}
	m.idx = flowIndex(m.flow, "hostname")
	m.loadStep()
	before := m.idx
	nm, _ := m.onKey("a")
	got := nm.(model)
	if got.idx != before {
		t.Fatalf("typing moved the step (idx %d -> %d)", before, got.idx)
	}
	if got.input != "a" {
		t.Fatalf("typing 'a' did not edit the field (input %q)", got.input)
	}
}

// returning to a text step shows what was entered before, not a blank field.
func TestInputStepRestoresValueOnBack(t *testing.T) {
	m := model{state: "wizard", flow: steps(), picks: map[string]string{"hostname": "box"}}
	m.idx = flowIndex(m.flow, "hostname")
	m.loadStep()
	if m.input != "box" {
		t.Fatalf("loadStep did not restore saved value (input %q)", m.input)
	}
}
