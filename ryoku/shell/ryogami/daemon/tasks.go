package main

import (
	"fmt"
	"sync"
	"time"
)

// The background jobs a client shows as filter-bar chips, in skwd-walld's task
// contract: a running scan, index build, download or capture, then its outcome.
const (
	taskRunning   = "running"
	taskCompleted = "completed"
	taskFailed    = "failed"
	taskCancelled = "cancelled"
)

const (
	evTaskStatus = "ryogami.task.status"
	// Progress fans out to every client, so it is rate-limited; state changes are not.
	taskProgressInterval = 250 * time.Millisecond
	taskKeepFinished     = 4
)

type taskCaps struct {
	Pause  bool `json:"pause"`
	Resume bool `json:"resume"`
	Stop   bool `json:"stop"`
}

type taskStatus struct {
	ID           string   `json:"id"`
	Kind         string   `json:"kind"`
	Label        string   `json:"label"`
	State        string   `json:"state"`
	Progress     int      `json:"progress"`
	Total        int      `json:"total"`
	Detail       string   `json:"detail,omitempty"`
	Capabilities taskCaps `json:"capabilities"`
}

type taskEntry struct {
	status taskStatus
	stop   func()
	sentAt time.Time
}

type taskRegistry struct {
	d     *daemon
	mu    sync.Mutex
	byID  map[string]*taskEntry
	order []string
}

func newTaskRegistry(d *daemon) *taskRegistry {
	return &taskRegistry{d: d, byID: map[string]*taskEntry{}}
}

// start registers or restarts a task; stop is nil when the job cannot be interrupted.
func (r *taskRegistry) start(id, kind, label string, total int, stop func()) {
	if r == nil {
		return
	}
	r.mu.Lock()
	e, ok := r.byID[id]
	if !ok {
		e = &taskEntry{}
		r.byID[id] = e
	} else {
		r.removeOrder(id)
	}
	r.order = append(r.order, id)
	e.status = taskStatus{ID: id, Kind: kind, Label: label, State: taskRunning, Total: total,
		Capabilities: taskCaps{Stop: stop != nil}}
	e.stop = stop
	st := r.stamp(e)
	r.mu.Unlock()
	r.publish(st)
}

// startOnce registers a task the first time a job reports; repeat reports leave it running.
func (r *taskRegistry) startOnce(id, kind, label string, total int) {
	if r == nil {
		return
	}
	r.mu.Lock()
	e, ok := r.byID[id]
	running := ok && e.status.State == taskRunning
	r.mu.Unlock()
	if !running {
		r.start(id, kind, label, total, nil)
	}
}

func (r *taskRegistry) progress(id string, done, total int, detail string) {
	if r == nil {
		return
	}
	r.mu.Lock()
	e, ok := r.byID[id]
	if !ok || e.status.State != taskRunning {
		r.mu.Unlock()
		return
	}
	e.status.Progress, e.status.Total, e.status.Detail = done, total, detail
	if time.Since(e.sentAt) < taskProgressInterval {
		r.mu.Unlock()
		return
	}
	st := r.stamp(e)
	r.mu.Unlock()
	r.publish(st)
}

// finish records a task's outcome; a positive total replaces the running count.
func (r *taskRegistry) finish(id, state string, total int, detail string) {
	if r == nil {
		return
	}
	r.mu.Lock()
	e, ok := r.byID[id]
	if !ok || e.status.State != taskRunning {
		r.mu.Unlock()
		return
	}
	e.status.State, e.status.Detail = state, detail
	if total > 0 {
		e.status.Total = total
		if state == taskCompleted {
			e.status.Progress = total
		}
	}
	e.status.Capabilities = taskCaps{}
	e.stop = nil
	st := r.stamp(e)
	r.trimFinished()
	r.mu.Unlock()
	r.publish(st)
}

func (r *taskRegistry) list() []taskStatus {
	out := []taskStatus{}
	if r == nil {
		return out
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, id := range r.order {
		out = append(out, r.byID[id].status)
	}
	return out
}

func (r *taskRegistry) control(id, action string) error {
	if r == nil {
		return fmt.Errorf("unknown task: %s", id)
	}
	r.mu.Lock()
	e, ok := r.byID[id]
	var stop func()
	if ok {
		stop = e.stop
	}
	r.mu.Unlock()
	switch {
	case !ok:
		return fmt.Errorf("unknown task: %s", id)
	case action == "stop" && stop != nil:
		// The job reports its own cancelled state once it has actually stopped.
		stop()
		return nil
	default:
		return fmt.Errorf("task %s cannot %s", id, action)
	}
}

func (r *taskRegistry) stamp(e *taskEntry) taskStatus {
	e.sentAt = time.Now()
	return e.status
}

func (r *taskRegistry) publish(st taskStatus) {
	if r.d != nil {
		r.d.broadcast(evTaskStatus, st)
	}
}

func (r *taskRegistry) removeOrder(id string) {
	for i, v := range r.order {
		if v == id {
			r.order = append(r.order[:i], r.order[i+1:]...)
			return
		}
	}
}

// trimFinished keeps only the newest few finished tasks, as skwd does.
func (r *taskRegistry) trimFinished() {
	finished := 0
	for i := len(r.order) - 1; i >= 0; i-- {
		id := r.order[i]
		if r.byID[id].status.State == taskRunning {
			continue
		}
		finished++
		if finished > taskKeepFinished {
			delete(r.byID, id)
			r.order = append(r.order[:i], r.order[i+1:]...)
		}
	}
}
