package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestOfflineMediaCheckDoesNotRunCurl(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "curl-invoked")
	if err := os.WriteFile(filepath.Join(dir, "curl"), []byte("#!/bin/sh\ntouch '"+marker+"'\nexit 1\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	t.Setenv("RYOKU_INSTALL_OFFLINE", dir)
	msg := isoCheckNetworkCmd()().(isoNetworkMsg)
	if !msg.online || msg.err != nil {
		t.Fatalf("offline readiness = %+v", msg)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatal("offline mode invoked curl")
	}
	m := newISOModel(defaultOptions())
	if m.current().title != "Installation media" {
		t.Fatal("offline wizard should describe the local medium")
	}
}

func TestMissingOfflineMediaCannotPassReadiness(t *testing.T) {
	t.Setenv("RYOKU_INSTALL_OFFLINE", filepath.Join(t.TempDir(), "missing"))
	msg := isoCheckNetworkCmd()().(isoNetworkMsg)
	if msg.online || msg.err == nil {
		t.Fatalf("missing payload accepted: %+v", msg)
	}
}

func TestOnlineStepUnchanged(t *testing.T) {
	t.Setenv("RYOKU_INSTALL_OFFLINE", "")
	m := newISOModel(defaultOptions())
	if m.current().title != "Network" {
		t.Fatal("online wizard changed")
	}
}

func TestOfflineMinimalDefaults(t *testing.T) {
	t.Setenv("RYOKU_INSTALL_OFFLINE", t.TempDir())
	m := newISOModel(defaultOptions())
	for key, want := range map[string]string{
		"filesystem": "ext4", "kernel": "latest", "compositor": "niri", "browser": "firefox",
	} {
		if m.picks[key] != want {
			t.Fatalf("%s = %s, want %s", key, m.picks[key], want)
		}
	}
	if len(m.selectedApps()) != 0 {
		t.Fatal("optional apps must be empty")
	}
	for _, key := range []string{"kernel", "compositor", "browser", "configuration", "shell"} {
		if len(isoChoices(key)) != 1 {
			t.Fatalf("unexpected alternatives for %s", key)
		}
	}
}
