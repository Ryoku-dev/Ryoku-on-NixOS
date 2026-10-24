package main

import (
	"bytes"
	"strings"
	"testing"
	"time"
)

func TestProgressReporterFormatsAndThrottles(t *testing.T) {
	var output bytes.Buffer
	now := time.Unix(100, 0)
	reporter := newProgressReporter(&output)
	reporter.now = func() time.Time { return now }

	reporter.report("download", 16, 100, false)
	now = now.Add(20 * time.Millisecond)
	reporter.report("download", 32, 100, false)
	now = now.Add(80 * time.Millisecond)
	reporter.report("download", 64, 100, false)
	reporter.report("extract", 1, 2, false)
	reporter.report("apply", 1, 1, true)

	got := strings.Split(strings.TrimSpace(output.String()), "\n")
	want := []string{
		"RYOSTORE-PROGRESS download 16 100",
		"RYOSTORE-PROGRESS download 64 100",
		"RYOSTORE-PROGRESS extract 1 2",
		"RYOSTORE-PROGRESS apply 1 1",
	}
	if len(got) != len(want) {
		t.Fatalf("progress lines = %q, want %q", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("progress line %d = %q, want %q", i, got[i], want[i])
		}
	}
}
