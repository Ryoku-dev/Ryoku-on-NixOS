package main

import (
	"reflect"
	"testing"
)

func TestFilterUnlockedBroadcastExpands(t *testing.T) {
	locked := map[string]bool{"eDP-1": true}
	connected := []string{"eDP-1", "DP-1", "HDMI-A-1"}
	got, ok := filterUnlockedOutputs(nil, connected, locked)
	if !ok || !reflect.DeepEqual(got, []string{"DP-1", "HDMI-A-1"}) {
		t.Fatalf("broadcast should expand to unlocked outputs, got %v ok=%v", got, ok)
	}
	got, ok = filterUnlockedOutputs([]string{"*"}, connected, locked)
	if !ok || !reflect.DeepEqual(got, []string{"DP-1", "HDMI-A-1"}) {
		t.Fatalf("'*' should expand to unlocked outputs, got %v ok=%v", got, ok)
	}
}

func TestFilterUnlockedNamedSet(t *testing.T) {
	locked := map[string]bool{"eDP-1": true}
	got, ok := filterUnlockedOutputs([]string{"eDP-1", "DP-1"}, nil, locked)
	if !ok || !reflect.DeepEqual(got, []string{"DP-1"}) {
		t.Fatalf("a named set should drop the locked output, got %v ok=%v", got, ok)
	}
}

func TestFilterUnlockedAllLockedVetoes(t *testing.T) {
	locked := map[string]bool{"eDP-1": true, "DP-1": true}
	if _, ok := filterUnlockedOutputs([]string{"eDP-1", "DP-1"}, nil, locked); ok {
		t.Fatal("a fully-locked named set must veto (ok=false), never fall back to broadcast")
	}
	if _, ok := filterUnlockedOutputs(nil, []string{"eDP-1", "DP-1"}, locked); ok {
		t.Fatal("a broadcast onto only locked outputs must veto, not paint them all")
	}
}

func TestFilterUnlockedNoLocksNoChange(t *testing.T) {
	got, ok := filterUnlockedOutputs([]string{"DP-1"}, nil, nil)
	if !ok || !reflect.DeepEqual(got, []string{"DP-1"}) {
		t.Fatalf("with no locks the request is unchanged, got %v ok=%v", got, ok)
	}
	if got, ok := filterUnlockedOutputs(nil, nil, map[string]bool{"x": true}); !ok || got != nil {
		t.Fatalf("broadcast with no connected outputs should stay broadcast, got %v ok=%v", got, ok)
	}
}
