package main

import (
	"bytes"
	"context"
	"errors"
	"log"
	"os"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"
)

const (
	dirEvents      = syscall.IN_CLOSE_WRITE | syscall.IN_MOVED_TO | syscall.IN_DELETE | syscall.IN_MOVED_FROM | syscall.IN_MOVE_SELF | syscall.IN_DELETE_SELF
	ancestorEvents = syscall.IN_ONLYDIR | syscall.IN_MOVE_SELF | syscall.IN_DELETE_SELF
	awaitEvents    = syscall.IN_CREATE | syscall.IN_MOVED_TO
	goneEvents     = syscall.IN_MOVE_SELF | syscall.IN_DELETE_SELF | syscall.IN_IGNORED
	// Events cover every path change; the timeout only bounds a missed one.
	resyncInterval = time.Minute
)

type paletteWatch struct {
	fd      int
	dir     string
	dirWd   int
	watched os.FileInfo
	// Watched ancestors of dir, each mapped to the child name it waits to see
	// created, or "" when only its own rename or removal matters.
	ancestors map[int]string
	read      func()
}

func watchPalette(path string, reload func() error) error {
	return watchPaletteContext(context.Background(), path, reload)
}

func watchPaletteContext(ctx context.Context, path string, reload func() error) error {
	fd, err := syscall.InotifyInit1(syscall.IN_CLOEXEC | syscall.IN_NONBLOCK)
	if err != nil {
		return err
	}
	file := os.NewFile(uintptr(fd), "palette-inotify")
	defer file.Close()
	dir, name := filepath.Dir(path), filepath.Base(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	stop := context.AfterFunc(ctx, func() { _ = file.SetReadDeadline(time.Now()) })
	defer stop()
	w := &paletteWatch{
		fd:        fd,
		dir:       dir,
		dirWd:     -1,
		ancestors: map[int]string{},
		read: func() {
			if err := reload(); err != nil {
				log.Printf("palette update ignored: %v", err)
			}
		},
	}
	if err := w.sync(); err != nil {
		return err
	}
	buffer := make([]byte, syscall.SizeofInotifyEvent+4096)
	for {
		if err := file.SetReadDeadline(time.Now().Add(resyncInterval)); err != nil {
			return err
		}
		// Checked after arming the deadline, so a cancel that lands later still
		// interrupts the read through the AfterFunc above.
		if err := ctx.Err(); err != nil {
			return err
		}
		n, err := file.Read(buffer)
		if err != nil {
			if errors.Is(err, os.ErrDeadlineExceeded) || errors.Is(err, syscall.EINTR) {
				if ctx.Err() == nil {
					if err := w.sync(); err != nil {
						return err
					}
				}
				continue
			}
			return err
		}
		changed, resync := false, false
		for offset := 0; offset+syscall.SizeofInotifyEvent <= n; {
			event := (*syscall.InotifyEvent)(unsafe.Pointer(&buffer[offset]))
			start := offset + syscall.SizeofInotifyEvent
			end := start + int(event.Len)
			if end > n {
				break
			}
			eventName := string(bytes.TrimRight(buffer[start:end], "\x00"))
			offset = end
			wd := int(event.Wd)
			switch {
			case event.Mask&syscall.IN_Q_OVERFLOW != 0:
				changed, resync = true, true
			case wd == w.dirWd:
				if eventName == name {
					changed = true
				}
				if event.Mask&goneEvents != 0 {
					resync = true
				}
			default:
				if awaited, ok := w.ancestors[wd]; ok && (event.Mask&goneEvents != 0 || (awaited != "" && eventName == awaited)) {
					resync = true
				}
			}
		}
		if resync {
			if err := w.sync(); err != nil {
				return err
			}
		}
		if changed {
			w.read()
		}
	}
}

// sync points the watches at whatever the path names now: the palette
// directory when it exists, and every ancestor so a rename or removal anywhere
// above it raises an event instead of going unnoticed.
func (w *paletteWatch) sync() error {
	for {
		current, err := os.Stat(w.dir)
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		if err != nil || (w.watched != nil && !os.SameFile(w.watched, current)) {
			w.dropDir()
		}
		if err == nil && w.watched == nil {
			wd, addErr := syscall.InotifyAddWatch(w.fd, w.dir, dirEvents)
			if addErr != nil && !errors.Is(addErr, syscall.ENOENT) {
				return addErr
			}
			if addErr == nil {
				w.dirWd, w.watched = wd, current
				// A file written before the watch attached produces no event.
				w.read()
			}
		}
		settled, err := w.watchAncestors()
		if err != nil {
			return err
		}
		if !settled {
			continue
		}
		// The directory may have appeared after the stat above but before the
		// ancestors were walked, which left nothing waiting for it.
		if _, err := os.Stat(w.dir); w.watched != nil || err != nil {
			return nil
		}
	}
}

func (w *paletteWatch) dropDir() {
	if w.dirWd >= 0 {
		_, _ = syscall.InotifyRmWatch(w.fd, uint32(w.dirWd))
	}
	w.dirWd, w.watched = -1, nil
}

// watchAncestors walks from the root down to the palette directory. It reports
// false when the tree changed under it, so sync takes another look.
func (w *paletteWatch) watchAncestors() (bool, error) {
	var chain []string
	for p := filepath.Dir(w.dir); ; p = filepath.Dir(p) {
		chain = append(chain, p)
		if p == filepath.Dir(p) {
			break
		}
	}
	next := map[int]string{}
	settled := true
	for i := len(chain) - 1; i >= 0; i-- {
		child := w.dir
		if i > 0 {
			child = chain[i-1]
		}
		_, err := os.Stat(child)
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return false, err
		}
		missing := err != nil
		mask := uint32(ancestorEvents)
		if missing {
			mask |= awaitEvents
		}
		wd, err := syscall.InotifyAddWatch(w.fd, chain[i], mask)
		if errors.Is(err, syscall.ENOENT) {
			settled = false
			break
		}
		if errors.Is(err, syscall.EACCES) {
			continue
		}
		if err != nil {
			return false, err
		}
		next[wd] = ""
		if missing {
			next[wd] = filepath.Base(child)
			// Created between the stat and the watch: no event will say so.
			if _, err := os.Stat(child); err == nil {
				settled = false
			}
			break
		}
	}
	for wd := range w.ancestors {
		if _, keep := next[wd]; !keep {
			_, _ = syscall.InotifyRmWatch(w.fd, uint32(wd))
		}
	}
	w.ancestors = next
	return settled, nil
}
