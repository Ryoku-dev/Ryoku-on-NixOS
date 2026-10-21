package doctor

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// fakeQs puts a qs on PATH that runs script, and returns the file the script
// records its helper's pid in.
func fakeQs(t *testing.T, script string) string {
	t.Helper()
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "helper.pid")
	body := "#!/bin/sh\nPIDFILE=" + pidFile + "\n" + script
	if err := os.WriteFile(filepath.Join(dir, "qs"), []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return pidFile
}

func assertGone(t *testing.T, pidFile string) {
	t.Helper()
	b, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatalf("the fake shell never started its helper: %v", err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(2 * time.Second); time.Now().Before(deadline); time.Sleep(50 * time.Millisecond) {
		if syscall.Kill(pid, 0) != nil {
			return
		}
	}
	t.Fatalf("the probe left process %d running", pid)
}

// A config that loads keeps running as a desktop; the probe must not wait for
// it to exit, and must not leave it, or anything it started, behind.
func TestProbeConfigStopsALoadedShell(t *testing.T) {
	pidFile := fakeQs(t, `sleep 300 & echo $! > "$PIDFILE"
echo "  INFO: Configuration Loaded"
exec sleep 300
`)
	start := time.Now()
	if report := probeConfig(); report != "" {
		t.Fatalf("a loaded config is no failure, got %q", report)
	}
	if took := time.Since(start); took > 10*time.Second {
		t.Fatalf("the probe waited %v for a running shell", took)
	}
	assertGone(t, pidFile)
}

func TestProbeConfigReportsALoadFailure(t *testing.T) {
	pidFile := fakeQs(t, `sleep 300 & echo $! > "$PIDFILE"
echo " ERROR: Failed to load configuration"
echo " ERROR:   caused by @shell.qml[13:1]: module \"shell.services\" is not installed"
exit 255
`)
	report := probeConfig()
	if !strings.Contains(report, `module "shell.services" is not installed`) {
		t.Fatalf("the failure report lost its cause: %q", report)
	}
	assertGone(t, pidFile)
}

// A shell that never says it loaded is still stopped once the window passes.
func TestProbeConfigGivesUpOnASilentShell(t *testing.T) {
	pidFile := fakeQs(t, `echo $$ > "$PIDFILE"
exec sleep 300
`)
	prev := shellProbeWindow
	shellProbeWindow = 300 * time.Millisecond
	t.Cleanup(func() { shellProbeWindow = prev })
	if report := probeConfig(); report != "" {
		t.Fatalf("silence is no failure, got %q", report)
	}
	assertGone(t, pidFile)
}
