package main

import (
	"strings"
	"testing"
)

func TestClickfingerDefaultIsEmitted(t *testing.T) {
	settings := genLua(defaultOverrides(), true)
	if !strings.Contains(settings, "clickfinger_behavior = true") {
		t.Fatalf("fresh settings do not enable clickfinger:\n%s", settings)
	}
}

func TestClickfingerExplicitFalseIsEmitted(t *testing.T) {
	o := defaultOverrides()
	o.Input.Clickfinger = false
	settings := genLua(o, true)
	if !strings.Contains(settings, "clickfinger_behavior = false") {
		t.Fatalf("explicit false does not override the shipped default:\n%s", settings)
	}
}
