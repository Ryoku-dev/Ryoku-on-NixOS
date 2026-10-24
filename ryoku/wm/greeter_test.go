package wm

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestPublishGreeterNumlock: the provider's apply records the session's
// keypad choice where the login greeter reads it, in the two words the
// greeter parses.
func TestPublishGreeterNumlock(t *testing.T) {
	file := filepath.Join(t.TempDir(), "greeter-numlock")
	t.Setenv("RYOKU_GREETER_NUMLOCK_FILE", file)

	read := func() string {
		b, err := os.ReadFile(file)
		if err != nil {
			t.Fatalf("hand-off not written: %v", err)
		}
		return strings.TrimSpace(string(b))
	}

	PublishGreeterNumlock(false)
	if got := read(); got != "off" {
		t.Fatalf("hand-off = %q, want off", got)
	}
	PublishGreeterNumlock(true)
	if got := read(); got != "on" {
		t.Fatalf("hand-off = %q, want on", got)
	}
}
