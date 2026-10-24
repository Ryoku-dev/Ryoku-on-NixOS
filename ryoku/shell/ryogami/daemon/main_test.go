package main

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

// TestMain points HOME and the XDG dirs at a throwaway tree, so no test can
// write into the developer's or CI runner's real config, cache, data, or trash.
func TestMain(m *testing.M) {
	root, err := os.MkdirTemp("", "ryogami-test-home-")
	if err != nil {
		fmt.Fprintln(os.Stderr, "ryogami tests: temp home:", err)
		os.Exit(1)
	}
	env := map[string]string{
		"HOME":            root,
		"XDG_CONFIG_HOME": filepath.Join(root, ".config"),
		"XDG_CACHE_HOME":  filepath.Join(root, ".cache"),
		"XDG_DATA_HOME":   filepath.Join(root, ".local", "share"),
		"XDG_STATE_HOME":  filepath.Join(root, ".local", "state"),
	}
	for k, v := range env {
		os.Setenv(k, v)
	}
	code := m.Run()
	os.RemoveAll(root)
	os.Exit(code)
}
