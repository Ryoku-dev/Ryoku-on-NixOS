package main

import (
	"bufio"
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeStore lays a desktop.json at the given path.
func writeStore(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// readGen reads one generated file back from a sandbox config tree.
func readGen(t *testing.T, dir, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(dir, "mango", name))
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return string(b)
}

// captureStdout runs fn with stdout redirected into a buffer and returns what
// it printed.
func captureStdout(t *testing.T, fn func() error) string {
	t.Helper()
	var buf bytes.Buffer
	prev := stdout
	stdout = bufio.NewWriter(&buf)
	err := fn()
	stdout.Flush()
	stdout = prev
	if err != nil {
		t.Fatal(err)
	}
	return buf.String()
}

// touchpadStatus runs input.touchpad status and returns what it printed.
func touchpadStatus(t *testing.T) string {
	t.Helper()
	out := captureStdout(t, func() error {
		return runAct([]string{"input.touchpad", "status"})
	})
	return strings.TrimSpace(out)
}
