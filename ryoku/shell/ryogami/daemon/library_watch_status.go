package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"io/fs"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	watchNative      = "native"
	watchPolling     = "polling"
	watchRecovering  = "recovering"
	watchUnavailable = "unavailable"
)

const libraryWatchDebounce = 800 * time.Millisecond

const inotifyMask = syscall.IN_CREATE | syscall.IN_CLOSE_WRITE | syscall.IN_DELETE |
	syscall.IN_MOVED_TO | syscall.IN_MOVED_FROM | syscall.IN_MOVE_SELF | syscall.IN_DELETE_SELF

var errNoWatchDirs = errors.New("no library directory to watch")

type libraryWatcher struct {
	mu              sync.Mutex
	state           string
	reason          string
	watchedDirs     int
	lastConvergence int64 // unix seconds of the last change-driven rescan
	rewatch         chan struct{}
}

var libraryWatch = &libraryWatcher{state: watchUnavailable, rewatch: make(chan struct{}, 1)}

func (w *libraryWatcher) set(state, reason string, dirs int) {
	w.mu.Lock()
	w.state, w.reason, w.watchedDirs = state, reason, dirs
	w.mu.Unlock()
}

func (w *libraryWatcher) setDirs(n int) {
	w.mu.Lock()
	w.watchedDirs = n
	w.mu.Unlock()
}

func (w *libraryWatcher) converged() {
	w.mu.Lock()
	w.lastConvergence = time.Now().Unix()
	w.mu.Unlock()
}

func (w *libraryWatcher) snapshot() map[string]interface{} {
	w.mu.Lock()
	defer w.mu.Unlock()
	return map[string]interface{}{
		"state":           w.state,
		"reason":          w.reason,
		"watchedDirs":     w.watchedDirs,
		"lastConvergence": w.lastConvergence,
	}
}

func (w *libraryWatcher) signalRewatch() {
	select {
	case w.rewatch <- struct{}{}:
	default:
	}
}

func init() {
	watchSetting("library.pollingFallback", func(d *daemon, _ string, _ interface{}) {
		libraryWatch.signalRewatch()
	})
}

func (d *daemon) startLibraryWatch() {
	for {
		if d.settingBool("library.pollingFallback") {
			d.pollLibrary("forced by setting")
			continue
		}
		fd, wds, err := d.inotifyWatchAll()
		if err != nil {
			d.pollLibrary("inotify unavailable: " + err.Error())
			continue
		}
		libraryWatch.set(watchNative, "", len(wds))
		reason := d.inotifyLoop(fd, wds)
		syscall.Close(fd)
		if reason == "error" {
			libraryWatch.set(watchRecovering, "watch stream interrupted; re-establishing", 0)
			time.Sleep(2 * time.Second)
		}
	}
}

func (d *daemon) inotifyWatchAll() (int, map[int32]string, error) {
	fd, err := syscall.InotifyInit1(syscall.IN_CLOEXEC)
	if err != nil {
		return -1, nil, err
	}
	cfg := d.config()
	absCache, _ := filepath.Abs(cfg.cacheDir())
	wds := map[int32]string{}
	seen := map[string]bool{}
	for _, root := range []string{cfg.wallpaperDir(), cfg.videoDir()} {
		if root == "" || seen[root] {
			continue
		}
		seen[root] = true
		_ = filepath.WalkDir(root, func(p string, e fs.DirEntry, werr error) error {
			if werr != nil || !e.IsDir() {
				return nil
			}
			if abs, _ := filepath.Abs(p); abs == absCache {
				return filepath.SkipDir
			}
			if p != root && strings.HasPrefix(e.Name(), ".") {
				return filepath.SkipDir
			}
			if wd, aerr := syscall.InotifyAddWatch(fd, p, inotifyMask); aerr == nil {
				wds[int32(wd)] = p
			}
			return nil
		})
	}
	if len(wds) == 0 {
		syscall.Close(fd)
		return -1, nil, errNoWatchDirs
	}
	return fd, wds, nil
}

func (d *daemon) inotifyLoop(fd int, wds map[int32]string) string {
	done := make(chan struct{})
	defer close(done)
	events := make(chan []inotifyEvent, 16)
	broke := make(chan struct{}, 1)
	go func() {
		buf := make([]byte, 64*1024)
		for {
			n, err := syscall.Read(fd, buf)
			if err != nil {
				if err == syscall.EINTR {
					continue
				}
				select {
				case broke <- struct{}{}:
				case <-done:
				}
				return
			}
			if n <= 0 {
				continue
			}
			evs := parseInotifyEvents(buf[:n])
			select {
			case events <- evs:
			case <-done:
				return
			}
		}
	}()

	var timer *time.Timer
	defer func() {
		if timer != nil {
			timer.Stop()
		}
	}()
	fire := make(chan struct{}, 1)
	schedule := func() {
		if timer != nil {
			timer.Stop()
		}
		timer = time.AfterFunc(libraryWatchDebounce, func() {
			select {
			case fire <- struct{}{}:
			default:
			}
		})
	}

	for {
		select {
		case <-libraryWatch.rewatch:
			return "rewatch"
		case <-broke:
			return "error"
		case evs := <-events:
			d.extendWatches(fd, wds, evs)
			if relevantWatchEvents(evs) {
				schedule()
			}
		case <-fire:
			d.rescan(false)
			libraryWatch.converged()
		}
	}
}

type inotifyEvent struct {
	wd   int32
	mask uint32
	name string
}

func parseInotifyEvents(buf []byte) []inotifyEvent {
	var out []inotifyEvent
	// Records are a 16-byte header plus a padded name of variable length.
	for i := 0; i+16 <= len(buf); {
		mask := binary.NativeEndian.Uint32(buf[i+4:])
		wd := int32(binary.NativeEndian.Uint32(buf[i:]))
		nlen := int(binary.NativeEndian.Uint32(buf[i+12:]))
		start := i + 16
		end := start + nlen
		if end > len(buf) {
			break
		}
		name := ""
		if nlen > 0 {
			name = string(bytes.TrimRight(buf[start:end], "\x00"))
		}
		out = append(out, inotifyEvent{wd: wd, mask: mask, name: name})
		i = end
	}
	return out
}

func (d *daemon) extendWatches(fd int, wds map[int32]string, evs []inotifyEvent) {
	grew := false
	for _, ev := range evs {
		if ev.mask&syscall.IN_ISDIR == 0 || ev.mask&(syscall.IN_CREATE|syscall.IN_MOVED_TO) == 0 {
			continue
		}
		parent, ok := wds[ev.wd]
		if !ok || ev.name == "" || strings.HasPrefix(ev.name, ".") {
			continue
		}
		root := filepath.Join(parent, ev.name)
		_ = filepath.WalkDir(root, func(p string, e fs.DirEntry, werr error) error {
			if werr != nil || !e.IsDir() {
				return nil
			}
			if p != root && strings.HasPrefix(e.Name(), ".") {
				return filepath.SkipDir
			}
			if wd, aerr := syscall.InotifyAddWatch(fd, p, inotifyMask); aerr == nil {
				wds[int32(wd)] = p
				grew = true
			}
			return nil
		})
	}
	if grew {
		libraryWatch.setDirs(len(wds))
	}
}

func relevantWatchEvents(evs []inotifyEvent) bool {
	for _, ev := range evs {
		if ev.mask&syscall.IN_ISDIR != 0 {
			return true
		}
		if ev.name == "" {
			continue
		}
		ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(ev.name), "."))
		if imageExts[ext] || videoExts[ext] {
			return true
		}
	}
	return false
}

func (d *daemon) pollLibrary(reason string) {
	libraryWatch.set(watchPolling, reason, 0)
	last := d.librarySignature()
	for {
		select {
		case <-libraryWatch.rewatch:
			return
		case <-time.After(pollInterval(d.settingNumber("library.pollingIntervalSeconds"))):
		}
		if !d.settingBool("library.pollingFallback") {
			if fd, _, err := d.inotifyWatchAll(); err == nil {
				syscall.Close(fd)
				return
			}
		}
		if sig := d.librarySignature(); sig != last {
			last = sig
			d.rescan(false)
			libraryWatch.converged()
		}
	}
}

func pollIntervalSeconds(seconds float64) int {
	if seconds < 15 {
		return 15
	}
	if seconds > 3600 {
		return 3600
	}
	return int(seconds)
}

func pollInterval(seconds float64) time.Duration {
	return time.Duration(pollIntervalSeconds(seconds)) * time.Second
}

func (d *daemon) libraryStatus() map[string]interface{} {
	status := libraryWatch.snapshot()
	status["pollingFallback"] = d.settingBool("library.pollingFallback")
	status["pollingIntervalSeconds"] = pollIntervalSeconds(d.settingNumber("library.pollingIntervalSeconds"))
	return status
}
