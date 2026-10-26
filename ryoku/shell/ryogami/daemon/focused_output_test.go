package main

import (
	"testing"

	wm "ryoku-wm"
)

func TestFocusedOutputNameUsesLiveFocusFrame(t *testing.T) {
	previousOutputs := outputs.list()
	wmCache.mu.Lock()
	previousFocus := wmCache.focusedOutput
	wmCache.focusedOutput = "DP-2"
	wmCache.mu.Unlock()
	t.Cleanup(func() {
		outputs.set(previousOutputs)
		wmCache.mu.Lock()
		wmCache.focusedOutput = previousFocus
		wmCache.mu.Unlock()
	})

	outputs.set([]wm.Output{
		{Name: "DP-1", Focused: true},
		{Name: "DP-2"},
	})
	if got := focusedOutputName(); got != "DP-2" {
		t.Fatalf("focused output = %q, want live focus DP-2", got)
	}

	wmCache.mu.Lock()
	wmCache.focusedOutput = ""
	wmCache.mu.Unlock()
	if got := focusedOutputName(); got != "DP-1" {
		t.Fatalf("focused output fallback = %q, want cached output DP-1", got)
	}
}
