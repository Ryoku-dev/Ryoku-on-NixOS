package main

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"golang.org/x/sys/unix"
)

const presenceFallbackInterval = 5 * time.Minute

type presenceFrame struct {
	Locked      bool `json:"locked"`
	DisplaysOff bool `json:"displaysOff"`
}

type presenceState struct {
	mu             sync.Mutex
	topic          *stateTopic
	marker         string
	generation     string
	lockProofValid func() bool
	frame          presenceFrame
}

func idleOutputStateDir() string {
	if dir := os.Getenv("RYOKU_IDLE_OUTPUT_STATE_DIR"); dir != "" {
		return dir
	}
	if dir := os.Getenv("XDG_RUNTIME_DIR"); dir != "" {
		return filepath.Join(dir, "ryoku-idle-output")
	}
	return filepath.Join(os.TempDir(), "ryoku-idle-output")
}

func (p *presenceState) refresh(lockChanged, displayChanged bool) {
	p.mu.Lock()
	if lockChanged {
		if _, err := os.Stat(p.marker); err == nil {
			p.frame.Locked = p.lockProofValid != nil && p.lockProofValid()
		} else {
			p.frame.Locked = false
		}
	}
	if displayChanged {
		_, err := os.Stat(p.generation)
		p.frame.DisplaysOff = err == nil
	}
	frame := p.frame
	p.mu.Unlock()
	body, _ := json.Marshal(frame)
	p.topic.publish(body)
}

func (p *presenceState) watchFallback(quit <-chan struct{}) {
	timer := time.NewTimer(presenceFallbackInterval)
	defer timer.Stop()
	for {
		select {
		case <-quit:
			return
		case <-timer.C:
			p.refresh(true, true)
			timer.Reset(presenceFallbackInterval)
		}
	}
}

func (p *presenceState) watch(quit <-chan struct{}) {
	p.refresh(true, true)
	fd, err := unix.InotifyInit1(unix.IN_CLOEXEC | unix.IN_NONBLOCK)
	if err != nil {
		log.Printf("ryoku-shell: presence watch unavailable, using slow reconciliation: %v", err)
		p.watchFallback(quit)
		return
	}
	defer unix.Close(fd)
	mask := uint32(unix.IN_CLOSE_WRITE | unix.IN_CREATE | unix.IN_DELETE | unix.IN_MOVED_TO | unix.IN_MOVED_FROM)
	runtimeWatch, err := unix.InotifyAddWatch(fd, filepath.Dir(p.marker), mask)
	if err != nil {
		log.Printf("ryoku-shell: presence watch unavailable, using slow reconciliation: %v", err)
		p.watchFallback(quit)
		return
	}
	outputWatch, err := unix.InotifyAddWatch(fd, filepath.Dir(p.generation), mask)
	if err != nil {
		log.Printf("ryoku-shell: presence watch unavailable, using slow reconciliation: %v", err)
		p.watchFallback(quit)
		return
	}
	stopFD, stopQuitWake, err := quitEventFD(quit)
	if err != nil {
		log.Printf("ryoku-shell: presence watch unavailable, using slow reconciliation: %v", err)
		p.watchFallback(quit)
		return
	}
	defer func() {
		stopQuitWake()
		unix.Close(stopFD)
	}()
	p.refresh(true, true)

	markerName := filepath.Base(p.marker)
	generationName := filepath.Base(p.generation)
	buf := make([]byte, 4096)
	for {
		pfds := []unix.PollFd{
			{Fd: int32(fd), Events: unix.POLLIN | unix.POLLERR},
			{Fd: int32(stopFD), Events: unix.POLLIN | unix.POLLERR},
		}
		if _, err := unix.Poll(pfds, -1); err != nil {
			if err == unix.EINTR {
				continue
			}
			log.Printf("ryoku-shell: presence watch failed, using slow reconciliation: %v", err)
			p.watchFallback(quit)
			return
		}
		if pfds[1].Revents != 0 {
			return
		}
		lockChanged, displayChanged := false, false
		for {
			n, err := unix.Read(fd, buf)
			if err != nil {
				break
			}
			for _, event := range decodeFileEvents(buf[:n]) {
				if event.mask&unix.IN_Q_OVERFLOW != 0 {
					lockChanged, displayChanged = true, true
				}
				if event.watch == int32(runtimeWatch) && event.name == markerName {
					lockChanged = true
				}
				if event.watch == int32(outputWatch) && event.name == generationName {
					displayChanged = true
				}
			}
		}
		if lockChanged || displayChanged {
			p.refresh(lockChanged, displayChanged)
		}
	}
}

func (d *daemon) startPresence() {
	outputDir := idleOutputStateDir()
	if err := os.MkdirAll(outputDir, 0o700); err != nil {
		log.Printf("ryoku-shell: create idle output state directory: %v", err)
	}
	p := &presenceState{
		topic:          d.registerTopic("presence"),
		marker:         lockMarker(),
		generation:     filepath.Join(outputDir, "generation"),
		lockProofValid: lockProofValid,
	}
	go p.watch(d.quit)
}
