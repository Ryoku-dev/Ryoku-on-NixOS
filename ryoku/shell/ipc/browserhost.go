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
	"time"

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
		defer close(done)
		if pipeErr == nil {
			defer wakeW.Write([]byte{0})
		}
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

	// Watch before the first send so a change between the two cannot be missed.
	watchFd := -1
	if pipeErr == nil {
		if fd, err := unix.InotifyInit1(unix.IN_CLOEXEC | unix.IN_NONBLOCK); err == nil {
			// The palette is replaced by rename, so watch its directory.
			if _, err := unix.InotifyAddWatch(fd, filepath.Dir(colorsPath),
				unix.IN_CLOSE_WRITE|unix.IN_CREATE|unix.IN_MOVED_TO); err == nil {
				watchFd = fd
			} else {
				unix.Close(fd)
			}
		}
	}
	if watchFd >= 0 {
		defer unix.Close(watchFd)
	}

	send()
	var last time.Time
	if fi, err := os.Stat(colorsPath); err == nil {
		last = fi.ModTime()
	}
	changed := func() {
		fi, err := os.Stat(colorsPath)
		if err != nil {
			return
		}
		if fi.ModTime().After(last) {
			last = fi.ModTime()
			send()
		}
	}

	if watchFd < 0 {
		ticker := time.NewTicker(browserHostFallbackInterval)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				return 0
			case <-ticker.C:
				browserHostFallbackPolls.Add(1)
				changed()
			}
		}
	}

	buf := make([]byte, 4096)
	for {
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
		select {
		case <-done:
			return 0
		default:
		}
		if pfds[0].Revents&unix.POLLIN != 0 {
			for {
				if _, err := unix.Read(watchFd, buf); err != nil {
					break
				}
			}
			changed()
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
