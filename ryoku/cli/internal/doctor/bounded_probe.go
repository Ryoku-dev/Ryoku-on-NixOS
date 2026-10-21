package doctor

import (
	"bytes"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

// runBoundedProbe starts cmd in its own process group and collects its
// combined output until answered says the output settles the question, the
// program exits, or window passes; then it stops the whole group. A probe that
// succeeds by staying up (a Quickshell config that loads is a running desktop)
// would otherwise hold doctor, and the update that runs it, open for good.
func runBoundedProbe(cmd *exec.Cmd, window time.Duration, answered func(string) bool) string {
	r, w, err := os.Pipe()
	if err != nil {
		return ""
	}
	cmd.Stdout, cmd.Stderr = w, w
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		r.Close()
		w.Close()
		return ""
	}
	w.Close()

	var mu sync.Mutex
	var out bytes.Buffer
	read := make(chan struct{})
	go func() {
		defer close(read)
		chunk := make([]byte, 4096)
		for {
			n, err := r.Read(chunk)
			mu.Lock()
			out.Write(chunk[:n])
			mu.Unlock()
			if err != nil {
				return
			}
		}
	}()
	exited := make(chan struct{})
	go func() {
		_ = cmd.Wait()
		close(exited)
	}()
	snapshot := func() string {
		mu.Lock()
		defer mu.Unlock()
		return out.String()
	}

	deadline := time.After(window)
	tick := time.NewTicker(100 * time.Millisecond)
	defer tick.Stop()
wait:
	for {
		select {
		case <-exited:
			break wait
		case <-deadline:
			break wait
		case <-tick.C:
			if answered(snapshot()) {
				break wait
			}
		}
	}

	pgid := cmd.Process.Pid
	_ = syscall.Kill(-pgid, syscall.SIGTERM)
	select {
	case <-exited:
	case <-time.After(2 * time.Second):
	}
	// whatever is left of the group, the leader included, goes now
	_ = syscall.Kill(-pgid, syscall.SIGKILL)
	<-exited
	// A child that left the group could keep the pipe open; the answer is in.
	select {
	case <-read:
	case <-time.After(time.Second):
	}
	r.Close()
	<-read
	return snapshot()
}
