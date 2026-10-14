package main

import (
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestPickerImportDirsCoverSystemLibdirs(t *testing.T) {
	dirs := strings.Split(pickerImportDirs(), string(os.PathListSeparator))
	have := make(map[string]bool, len(dirs))
	for _, dir := range dirs {
		have[dir] = true
	}
	for _, want := range []string{"/usr/lib/qt6/qml", "/usr/lib64/qt6/qml"} {
		if !have[want] {
			t.Errorf("picker import dirs %q do not include %q", dirs, want)
		}
	}
}

func TestConcurrentEagerLaunchAndEnsurePreserveOpenRequest(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("RYOGAMI_HEADLESS", "")
	m := &managedProcess{
		qml: "/tmp/ryogami-launch-race-test.qml",
		command: func(string, ...string) *exec.Cmd {
			return exec.Command("sleep", "30")
		},
	}
	t.Cleanup(m.kill)

	start := make(chan struct{})
	launchDone := make(chan struct{})
	ensureDone := make(chan bool)
	go func() {
		<-start
		m.launch()
		close(launchDone)
	}()
	go func() {
		<-start
		ensureDone <- m.ensure()
	}()
	close(start)

	select {
	case <-launchDone:
	case <-time.After(3 * time.Second):
		t.Fatal("eager launch did not finish")
	}
	select {
	case ready := <-ensureDone:
		if ready {
			t.Fatal("picker reported ready before subscribing")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("ensure did not finish")
	}

	m.mu.Lock()
	cmd := m.cmd
	pending := m.pending.name
	m.mu.Unlock()
	if cmd == nil {
		t.Fatal("concurrent launch did not start a picker process")
	}
	visible := false
	for _, entry := range cmd.Env {
		if entry == "RYOGAMI_START_VISIBLE=1" {
			visible = true
			break
		}
	}
	if !visible && pending != "ryogami.wall.toggle" {
		t.Fatal("hidden eager launch won without retaining the open request")
	}
}

func TestSecondOpenDuringVisibleColdStartDoesNotQueueToggle(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("RYOGAMI_HEADLESS", "")
	m := &managedProcess{
		qml: "/tmp/ryogami-visible-launch-test.qml",
		command: func(string, ...string) *exec.Cmd {
			return exec.Command("sleep", "30")
		},
	}
	t.Cleanup(m.kill)

	if m.ensure() {
		t.Fatal("cold-started picker reported ready before subscribing")
	}
	if m.ensure() {
		t.Fatal("visible picker reported ready before subscribing")
	}
	delivered := 0
	m.subscribed(1, func(string, map[string]interface{}) {
		delivered++
	})
	if delivered != 0 {
		t.Fatalf("visible cold start delivered %d redundant toggle events", delivered)
	}
}
