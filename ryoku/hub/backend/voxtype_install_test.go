package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestInstallCancelHelper(t *testing.T) {
	if os.Getenv("RYOKU_CANCEL_HELPER") != "1" {
		return
	}
	cmd := exec.Command("sh", "-c", `trap '' TERM; sh -c 'trap "" TERM; echo $$ > "$RYOKU_CHILD_PID"; while :; do sleep 1; done' & wait`)
	if err := runCancelableInstall(cmd); err == nil {
		os.Exit(3)
	}
	os.Exit(0)
}

func TestInstallCancellationStopsDescendants(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "child.pid")
	cmd := exec.Command(os.Args[0], "-test.run=^TestInstallCancelHelper$")
	cmd.Env = append(os.Environ(), "RYOKU_CANCEL_HELPER=1", "RYOKU_CHILD_PID="+marker)
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for !fileExists(marker) && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if !fileExists(marker) {
		cmd.Process.Kill()
		t.Fatal("child did not start")
	}
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(6 * time.Second):
		cmd.Process.Kill()
		t.Fatal("cancellation did not terminate")
	}
	data, _ := os.ReadFile(marker)
	pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	stat, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "stat"))
	if err == nil && !strings.Contains(string(stat), ") Z ") {
		t.Fatalf("descendant %d survived cancellation: %s", pid, stat)
	}
}
