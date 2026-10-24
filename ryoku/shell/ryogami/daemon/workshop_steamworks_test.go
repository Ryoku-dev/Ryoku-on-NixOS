package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSteamworksSilentChildIsStopped(t *testing.T) {
	d := newSettingsDaemon(t)
	ch := d.events.subscribe()
	defer d.events.unsubscribe(ch)
	w := &workshopLib{d: d}
	setWorkshopDownloadTimeouts(t, 25*time.Millisecond, 2*time.Second)

	bin := t.TempDir()
	helper := filepath.Join(bin, steamHelperBin)
	if err := os.WriteFile(helper, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	// The fake helper resolves first; the rest of PATH still finds sleep.
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	oldCommand := steamworksCommandContext
	var child *exec.Cmd
	steamworksCommandContext = func(ctx context.Context, _ string, _ ...string) *exec.Cmd {
		child = exec.CommandContext(ctx, "/bin/sh", "-c", "exec sleep 30")
		return child
	}
	t.Cleanup(func() { steamworksCommandContext = oldCommand })

	w.runDownload("1", false)
	event := workshopTerminalEvent(t, ch)
	if event["status"] != "error" {
		t.Fatalf("status = %v, want error", event["status"])
	}
	message, _ := event["message"].(string)
	if !strings.Contains(message, "stopped responding and was stopped") ||
		!strings.Contains(message, "start Steam") {
		t.Fatalf("message is not actionable: %q", message)
	}
	if child == nil || child.ProcessState == nil || child.ProcessState.Success() {
		t.Fatalf("silent helper was not killed: %#v", child)
	}
}
