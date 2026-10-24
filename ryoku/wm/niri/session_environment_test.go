package main

import (
	"bufio"
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestRunEnvironmentReplacesStaleProviderHandle(t *testing.T) {
	root := t.TempDir()
	pidDir := filepath.Join(root, "42")
	if err := os.Mkdir(pidDir, 0o700); err != nil {
		t.Fatal(err)
	}
	runtimeDir := t.TempDir()
	liveSocket := filepath.Join(runtimeDir, "niri.wayland-1.2060.sock")
	if err := os.WriteFile(liveSocket, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	body := []byte("XDG_SESSION_ID=9\x00XDG_RUNTIME_DIR=" + runtimeDir +
		"\x00WAYLAND_DISPLAY=wayland-1\x00NIRI_SOCKET=" +
		filepath.Join(runtimeDir, "niri.wayland-1.1000.sock") +
		"\x00SECRET=nope\x00")
	if err := os.WriteFile(filepath.Join(pidDir, "environ"), body, 0o600); err != nil {
		t.Fatal(err)
	}

	oldRoot, oldOut, oldAlive := sessionEnvironmentRoot, stdout, aliveCheck
	sessionEnvironmentRoot = root
	aliveCheck = func(path string) bool { return path == liveSocket }
	var output bytes.Buffer
	stdout = bufio.NewWriter(&output)
	t.Cleanup(func() {
		sessionEnvironmentRoot = oldRoot
		stdout = oldOut
		aliveCheck = oldAlive
	})

	if err := runEnvironment([]string{"42"}); err != nil {
		t.Fatal(err)
	}
	if err := stdout.Flush(); err != nil {
		t.Fatal(err)
	}
	if got, want := output.String(), "NIRI_SOCKET="+liveSocket+"\x00"; got != want {
		t.Fatalf("environment output = %q, want %q", got, want)
	}
}
