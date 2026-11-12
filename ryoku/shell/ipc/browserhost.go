package main

import (
	"encoding/binary"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/unix"
)

// WebExtension native-messaging host (host name "ryoku_theme"). The browser
// launches it when the Ryoku extension connects; it streams the live palette
// (colors.json) as {mode,colors} on connect and on every change, until the
// browser closes stdin. Framing is the native-messaging standard: a 4-byte
// native-endian length prefix then UTF-8 JSON. See ryoku/browser.
func runBrowserHost() int {
	return serveBrowserHost(os.Stdin, os.Stdout, matugenColorsPath())
}

// browserHostFallbackPolls counts stat polls made when inotify is unavailable.
// It stays zero on the normal event-driven path.
var browserHostFallbackPolls atomic.Int64

// browserHostBaselineHook, when set by a test, runs after the change baseline
// is recorded and before the initial palette is read.
var browserHostBaselineHook func()

// browserHostFallbackInterval paces polling only when the colors directory
// cannot be watched (not yet created, or inotify exhausted).
const browserHostFallbackInterval = 500 * time.Millisecond

func serveBrowserHost(in io.Reader, out io.Writer, colorsPath string) int {
	var outMu sync.Mutex
	send := func() {
		msg := browserPaletteAt(colorsPath)
		if msg == nil {
			return
		}
		b, err := json.Marshal(msg)
		if err != nil {
			return
		}
		var hdr [4]byte
		binary.LittleEndian.PutUint32(hdr[:], uint32(len(b)))
		outMu.Lock()
		defer outMu.Unlock()
		out.Write(hdr[:])
		out.Write(b)
	}

	// A pipe wakes the watcher when the browser disconnects, so it can block in
	// poll(2) instead of waking on a timer.
	wakeR, wakeW, pipeErr := os.Pipe()
	if pipeErr == nil {
		defer wakeR.Close()
		defer wakeW.Close()
	}

	// Drain inbound frames; EOF means the browser disconnected, so exit.
	done := make(chan struct{})
	go func() {
		// Deferred calls run last-in first-out: publish "done" before waking
		// the watcher, so it never wakes to find the browser still connected.
		if pipeErr == nil {
			defer wakeW.Write([]byte{0})
		}
		defer close(done)
		var hdr [4]byte
		for {
			if _, err := io.ReadFull(in, hdr[:]); err != nil {
				return
			}
			n := binary.LittleEndian.Uint32(hdr[:])
			if n == 0 || n > 1<<20 {
				return
			}
			if _, err := io.CopyN(io.Discard, in, int64(n)); err != nil {
				return
			}
		}
	}()

	// The palette is replaced by rename, so watch its directory.
	openWatch := func() int {
		if pipeErr != nil {
			return -1
		}
		fd, err := unix.InotifyInit1(unix.IN_CLOEXEC | unix.IN_NONBLOCK)
		if err != nil {
			return -1
		}
		if _, err := unix.InotifyAddWatch(fd, filepath.Dir(colorsPath),
			unix.IN_CLOSE_WRITE|unix.IN_CREATE|unix.IN_MOVED_TO|
				unix.IN_DELETE_SELF|unix.IN_MOVE_SELF); err != nil {
			unix.Close(fd)
			return -1
		}
		return fd
	}

	// Watch before the baseline so a change in between cannot be missed.
	watchFd := openWatch()
	defer func() {
		if watchFd >= 0 {
			unix.Close(watchFd)
		}
	}()

	// Identify the file by more than its mtime: filesystem timestamps can be
	// coarse, so two quick updates may share one, while a replacement by
	// rename always changes the inode.
	type fileID struct {
		mtime time.Time
		size  int64
		ino   uint64
	}
	identify := func() (fileID, bool) {
		fi, err := os.Stat(colorsPath)
		if err != nil {
			return fileID{}, false
		}
		id := fileID{mtime: fi.ModTime(), size: fi.Size()}
		if st, ok := fi.Sys().(*syscall.Stat_t); ok {
			id.ino = st.Ino
		}
		return id, true
	}

	// Record the baseline BEFORE reading the palette: an update landing after
	// this point differs from it and is sent, whereas recording it afterwards
	// would swallow an update that arrived in between.
	last, _ := identify()
	if browserHostBaselineHook != nil {
		browserHostBaselineHook()
	}
	send()

	changed := func() {
		if id, ok := identify(); ok && id != last {
			last = id
			send()
		}
	}
	// lose drops a dead watch and tries to re-establish it straight away (the
	// directory may just have been replaced); otherwise polling takes over
	// until it can be watched again.
	lose := func() {
		if watchFd >= 0 {
			unix.Close(watchFd)
		}
		watchFd = openWatch()
		changed() // resync with whatever happened while unwatched
	}

	const lostMask = unix.IN_IGNORED | unix.IN_DELETE_SELF | unix.IN_MOVE_SELF | unix.IN_UNMOUNT
	buf := make([]byte, 4096)
	// drain reads queued events and reports whether the watch itself died.
	drain := func() (lost bool) {
		for {
			n, err := unix.Read(watchFd, buf)
			if err != nil {
				return lost || (err != unix.EAGAIN && err != unix.EINTR)
			}
			for off := 0; off+unix.SizeofInotifyEvent <= n; {
				ev := (*unix.InotifyEvent)(unsafe.Pointer(&buf[off]))
				if ev.Mask&lostMask != 0 {
					lost = true
				}
				off += unix.SizeofInotifyEvent + int(ev.Len)
			}
		}
	}

	for {
		if watchFd < 0 {
			// Not watchable (directory missing, or inotify unavailable):
			// poll slowly and try to get back to event-driven.
			select {
			case <-done:
				return 0
			case <-time.After(browserHostFallbackInterval):
			}
			browserHostFallbackPolls.Add(1)
			watchFd = openWatch() // before changed(): no gap between the two
			changed()
			continue
		}

		pfds := []unix.PollFd{
			{Fd: int32(watchFd), Events: unix.POLLIN},
			{Fd: int32(wakeR.Fd()), Events: unix.POLLIN},
		}
		if _, err := unix.Poll(pfds, -1); err != nil {
			if err == unix.EINTR {
				continue
			}
			return 0
		}
		if pfds[1].Revents != 0 {
			return 0 // browser disconnected
		}
		switch rev := pfds[0].Revents; {
		case rev&(unix.POLLERR|unix.POLLHUP|unix.POLLNVAL) != 0:
			lose()
		case rev&unix.POLLIN != 0:
			if drain() {
				lose()
			} else {
				changed()
			}
		}
	}
}

// browserPaletteAt reads colors.json and returns the payload the extension reads:
// snake_case M3 roles plus base16, and a light/dark mode from surface luminance.
func browserPaletteAt(path string) map[string]any {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var raw map[string]string
	if json.Unmarshal(b, &raw) != nil {
		return nil
	}
	colors := map[string]string{}
	for _, kv := range matugenRoleKeys { // camelCase in colors.json -> snake_case
		if v := raw[kv[1]]; v != "" {
			colors[kv[0]] = v
		}
	}
	for k, v := range raw {
		if strings.HasPrefix(k, "color") || k == "background" || k == "foreground" || k == "cursor" {
			colors[k] = v
		}
	}
	if len(colors) == 0 {
		return nil
	}
	return map[string]any{"mode": staticPaletteMode(colors), "colors": colors}
}
