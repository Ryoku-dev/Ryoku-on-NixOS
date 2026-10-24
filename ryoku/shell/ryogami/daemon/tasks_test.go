package main

import (
	"fmt"
	"testing"
)

func TestTaskStopRunsOnlyWhileRunning(t *testing.T) {
	r := newTaskRegistry(nil)
	stops := 0
	r.start("download:a", "download", "Download", 100, func() { stops++ })
	if caps := r.list()[0].Capabilities; !caps.Stop || caps.Pause || caps.Resume {
		t.Fatalf("a cancellable download offers %+v, want stop only", caps)
	}
	if err := r.control("download:a", "pause"); err == nil {
		t.Fatal("pause must be refused: no job here can pause")
	}
	if err := r.control("download:a", "stop"); err != nil || stops != 1 {
		t.Fatalf("stop: err %v, stops %d", err, stops)
	}
	r.finish("download:a", taskCancelled, 0, "")
	if err := r.control("download:a", "stop"); err == nil || stops != 1 {
		t.Fatalf("a finished task must not stop again: err %v, stops %d", err, stops)
	}
	if st := r.list()[0]; st.State != taskCancelled || st.Capabilities.Stop {
		t.Fatalf("finished task = %+v, want cancelled with no controls", st)
	}
}

func TestTaskFinishIgnoresUnknownAndSettled(t *testing.T) {
	r := newTaskRegistry(nil)
	r.finish("scan", taskCompleted, 3, "")
	if len(r.list()) != 0 {
		t.Fatal("finishing a task that never started must not invent one")
	}
	r.start("scan", "scan", "Scan", 0, nil)
	r.finish("scan", taskCompleted, 12, "")
	r.finish("scan", taskFailed, 0, "late")
	if st := r.list()[0]; st.State != taskCompleted || st.Progress != 12 || st.Total != 12 {
		t.Fatalf("scan = %+v, want the first outcome with 12/12 kept", st)
	}
}

func TestTaskKeepsNewestFinished(t *testing.T) {
	r := newTaskRegistry(nil)
	r.start("index", "semantic", "Index", 10, nil)
	for i := range 6 {
		id := fmt.Sprintf("download:%d", i)
		r.start(id, "download", "Download", 100, nil)
		r.finish(id, taskCompleted, 0, "")
	}
	got := r.list()
	if len(got) != 1+taskKeepFinished {
		t.Fatalf("kept %d tasks, want the running one plus %d finished", len(got), taskKeepFinished)
	}
	if got[0].ID != "index" || got[1].ID != "download:2" || got[len(got)-1].ID != "download:5" {
		t.Fatalf("order = %v, want index then download:2..5", got)
	}
}
