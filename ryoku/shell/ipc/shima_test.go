package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func shimaTestDaemon(t *testing.T, style string) *daemon {
	t.Helper()
	path := filepath.Join(t.TempDir(), "shell.json")
	if err := os.WriteFile(path, []byte(`{"barStyle":"`+style+`","keep":{"value":42}}`), 0600); err != nil {
		t.Fatal(err)
	}
	return &daemon{settings: newSettingsStore(path), quit: make(chan struct{})}
}

func shimaTestLauncher(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	root := filepath.Join(dir, "runtime")
	os.Mkdir(root, 0700)
	os.WriteFile(filepath.Join(root, "shell.qml"), []byte("ShellRoot {}"), 0600)
	path := filepath.Join(dir, "ryoku-shima")
	os.WriteFile(path, []byte("#!/bin/sh\nprintf '%s\\n' '"+root+"'\n"), 0700)
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("NIRI_SOCKET", "/test/niri.sock")
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	// A host with Shima installed has a managed profile under the real state
	// home, which desktopSelection prefers over PATH.
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	return path
}

func TestShimaSelectionUsesInstalledRuntime(t *testing.T) {
	d := shimaTestDaemon(t, "iris")
	shimaTestLauncher(t)
	t.Setenv("RYOKU_SHIMA_ENABLE", "0")
	if key, _ := d.desktopSelection(); key != "native" {
		t.Fatal(key)
	}
	t.Setenv("RYOKU_SHIMA_ENABLE", "")
	if key, _ := d.desktopSelection(); key == "native" {
		t.Fatal("installed runtime not selected")
	}
	t.Setenv("NIRI_SOCKET", "")
	if key, _ := d.desktopSelection(); key != "native" {
		t.Fatal("non-Niri session selected Shima")
	}
}

func TestShimaCommandHasPrivateReadinessAndManagedEnvironment(t *testing.T) {
	d := shimaTestDaemon(t, "iris")
	shimaTestLauncher(t)
	t.Setenv("RYOKU_SHIMA_ENABLE", "1")
	cmd, run, err := d.desktopCommand()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Remove(run.ready); activeShimaRoot.Store("") })
	if !run.shima || cmd.SysProcAttr == nil || !cmd.SysProcAttr.Setpgid {
		t.Fatal("not supervised as an owned group")
	}
	if !strings.Contains(strings.Join(cmd.Env, "\n"), "RYOKU_SHIMA_MANAGED=1") {
		t.Fatal("missing ownership")
	}
	if shimaReady(run.ready, 123) {
		t.Fatal("empty marker accepted")
	}
	os.WriteFile(run.ready, []byte("124"), 0600)
	if shimaReady(run.ready, 123) {
		t.Fatal("wrong process accepted")
	}
	os.WriteFile(run.ready, []byte("123"), 0600)
	if !shimaReady(run.ready, 123) {
		t.Fatal("matching process rejected")
	}
}

func TestShimaFallbackPreservesSettingsAndPreviousStyle(t *testing.T) {
	d := shimaTestDaemon(t, "iris")
	d.shimaPrevious = "python"
	d.fallbackShima("test")
	raw, err := os.ReadFile(d.settings.path)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	json.Unmarshal(raw, &m)
	if m["barStyle"] != "python" || m["keep"].(map[string]any)["value"] != float64(42) {
		t.Fatal(string(raw))
	}
}

func TestShimaReadinessTimeoutStopsOwnedProcess(t *testing.T) {
	d := shimaTestDaemon(t, "iris")
	launcher := shimaTestLauncher(t)
	t.Setenv("RYOKU_SHIMA_ENABLE", "1")
	cmd := exec.Command("sleep", "30")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer cmd.Process.Kill()
	run := &desktopRun{shima: true, key: launcher, ready: filepath.Join(t.TempDir(), "not-ready")}
	exited := make(chan struct{})
	done := make(chan error, 1)
	go func() { done <- cmd.Wait(); close(exited) }()
	go d.watchDesktop(cmd, run, exited, 10*time.Millisecond)
	select {
	case <-done:
	case <-time.After(4 * time.Second):
		t.Fatal("unready root left running")
	}
	if !run.failed.Load() || run.intentional.Load() {
		t.Fatal("readiness failure not recorded")
	}
}

func TestShimaSelectionChangeStopsOldRootBeforeReplacement(t *testing.T) {
	d := shimaTestDaemon(t, "python")
	t.Setenv("RYOKU_SHIMA_ENABLE", "0")
	cmd := exec.Command("sleep", "30")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer cmd.Process.Kill()
	run := &desktopRun{shima: true, key: "old-shima", ready: ""}
	exited := make(chan struct{})
	done := make(chan error, 1)
	go func() { done <- cmd.Wait(); close(exited) }()
	go d.watchDesktop(cmd, run, exited, time.Second)
	select {
	case <-done:
	case <-time.After(4 * time.Second):
		t.Fatal("old root left running after switch")
	}
	if !run.intentional.Load() || run.failed.Load() {
		t.Fatal("selection change classified as crash")
	}
}

func TestShimaFamilyWritePreservesSettings(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	os.WriteFile(path, []byte(`{"panelFamily":"iris","enabledPanels":["irisBar"],"keep":42}`), 0600)
	if err := writeShimaFamily(path, "waffle", []string{"wBar", "wBackground"}); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(path)
	var v map[string]any
	json.Unmarshal(b, &v)
	if v["panelFamily"] != "waffle" || v["keep"] != float64(42) {
		t.Fatal(string(b))
	}
	if len(v["enabledPanels"].([]any)) != 3 {
		t.Fatal(string(b))
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0600 {
		t.Fatal("file mode changed")
	}
}

func TestShimaFamilyWriteRejectsInvalidAndManagedFiles(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	original := []byte(`{"panelFamily":"iris"}`)
	os.WriteFile(path, original, 0600)
	if err := writeShimaFamily(path, "invalid", nil); err == nil {
		t.Fatal("accepted invalid family")
	}
	b, _ := os.ReadFile(path)
	if string(b) != string(original) {
		t.Fatal("changed config after rejection")
	}
	link := path + ".link"
	os.Symlink(path, link)
	if err := writeShimaFamily(link, "ii", nil); err == nil {
		t.Fatal("replaced managed config")
	}
	b, _ = os.ReadFile(path)
	if string(b) != string(original) {
		t.Fatal("changed symlink target")
	}
}

func TestShimaWindowCleanupIsScopedToRuntimeAndToken(t *testing.T) {
	token := "/run/user/1000/owned-ready"
	root := "/nix/store/example-inir/share/quickshell/inir"
	env := "HOME=/home/user\x00RYOKU_SHIMA_READY_FILE=" + token + "\x00"
	cases := []struct {
		argv []string
		env  string
		want bool
	}{
		{[]string{"qs", "-p", root + "/settings.qml"}, env, true},
		{[]string{".quickshell-wrapped", "-p", root + "/waffle-settings.qml"}, env, true},
		{[]string{"qs", "-p", root + "/settings.qml"}, "RYOKU_SHIMA_READY_FILE=/other", false},
		{[]string{"qs", "-p", "/other/hub.qml"}, env, false},
		{[]string{"qs", "-p", root + "/settings.qml", "ipc", "call", "settings", "open"}, env, false},
		{[]string{"firefox", "-p", root}, env, false},
	}
	for _, c := range cases {
		if got := ownedShimaWindow(c.argv, c.env, root, token); got != c.want {
			t.Fatalf("%v: got %v", c.argv, got)
		}
	}
}

func TestShimaStaleFailureDoesNotOverwriteNewSelection(t *testing.T) {
	d := shimaTestDaemon(t, "python")
	d.shimaPrevious = "qsbar"
	d.fallbackShima("late exit")
	if d.settings.raw["barStyle"] != "python" {
		t.Fatal("stale failure replaced the newer selection")
	}
}

func TestShimaBrokenFallbackCannotRestartLoop(t *testing.T) {
	d := shimaTestDaemon(t, "iris")
	shimaTestLauncher(t)
	t.Setenv("RYOKU_SHIMA_ENABLE", "")
	d.settings.path = "/proc/ryoku-shima-no-config/shell.json"
	d.fallbackShima("test failure")
	if key, _ := d.desktopSelection(); key != "native" {
		t.Fatal("failed persistence permits a restart loop")
	}
}

func TestShimaManagedProfileResolvesNewGeneration(t *testing.T) {
	d := shimaTestDaemon(t, "iris")
	t.Setenv("RYOKU_SHIMA_ENABLE", "")
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("NIRI_SOCKET", "/test/niri.sock")
	profile := filepath.Join(shimaStateHome(), "ryoku", "subshells", "iris", "profile")
	os.MkdirAll(filepath.Dir(profile), 0700)
	generation := func() string {
		path := t.TempDir()
		os.Mkdir(filepath.Join(path, "bin"), 0700)
		os.WriteFile(filepath.Join(path, "bin", "ryoku-shima"), []byte("test"), 0700)
		return path
	}
	first, second := generation(), generation()
	os.Symlink(first, profile)
	a, _ := d.desktopSelection()
	os.Remove(profile)
	os.Symlink(second, profile)
	b, _ := d.desktopSelection()
	if a == b || a != filepath.Join(first, "bin", "ryoku-shima") || b != filepath.Join(second, "bin", "ryoku-shima") {
		t.Fatalf("generation change not detected: %q %q", a, b)
	}
}

// startFakeQs runs a throwaway process whose argv reads as a quickshell
// instance, so the stray scan can be exercised against a real /proc entry.
func startFakeQs(t *testing.T, env []string, args ...string) int {
	t.Helper()
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("sh not available")
	}
	cmd := exec.Command(sh)
	cmd.Args = append([]string{"qs", "-c", "sleep 30; :"}, args...)
	cmd.Env = append(os.Environ(), env...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL); _ = cmd.Wait() })
	return cmd.Process.Pid
}

func waitStray(d *daemon, pid int) bool {
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		for _, p := range d.strayPids() {
			if p == pid {
				return true
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	return false
}

// A daemon that starts after its predecessor was killed (KillMode=process)
// has not resolved the Shima root yet, so the orphaned root has to be found
// by its supervision marker or two desktops render at once.
func TestStrayScanFindsOrphanedShimaRootBeforeSelection(t *testing.T) {
	activeShimaRoot.Store("")
	t.Cleanup(func() { activeShimaRoot.Store("") })
	root := filepath.Join(t.TempDir(), "inir")
	os.Mkdir(root, 0700)
	d := &daemon{proc: map[string]*exec.Cmd{}}
	orphan := startFakeQs(t, []string{"RYOKU_SHIMA_MANAGED=1"}, "-p", root)
	window := startFakeQs(t, []string{"RYOKU_SHIMA_MANAGED=1"}, "-p", filepath.Join(root, "settings.qml"))
	foreign := startFakeQs(t, nil, "-p", root)
	if !waitStray(d, orphan) {
		t.Fatal("orphaned Shima root not reaped by a fresh daemon")
	}
	for _, p := range d.strayPids() {
		if p == window || p == foreign {
			t.Fatalf("pid %d is not a supervised root", p)
		}
	}
}

// While Shima is the selected root, a leftover native shell is still a second
// desktop and must be reaped.
func TestStrayScanFindsNativeShellWhileShimaActive(t *testing.T) {
	activeShimaRoot.Store(filepath.Join(t.TempDir(), "inir"))
	t.Cleanup(func() { activeShimaRoot.Store("") })
	d := &daemon{proc: map[string]*exec.Cmd{}}
	sel := []string{"-c", "shell"}
	if shellDir != "" {
		sel = []string{"-p", filepath.Join(shellDir, "quickshell", "shell")}
	}
	pid := startFakeQs(t, nil, sel...)
	if !waitStray(d, pid) {
		t.Fatal("native shell stray missed while Shima is active")
	}
}
