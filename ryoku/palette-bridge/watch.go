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
	read := func() {
		if err := reload(); err != nil {
			log.Printf("palette update ignored: %v", err)
		}
	}
	var watched os.FileInfo
	wd := -1
	buffer := make([]byte, syscall.SizeofInotifyEvent+4096)
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		current, statErr := os.Stat(dir)
		if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
			return statErr
		}
		if statErr == nil && (watched == nil || !os.SameFile(watched, current)) {
			if wd >= 0 {
				_, _ = syscall.InotifyRmWatch(fd, uint32(wd))
			}
			wd, err = syscall.InotifyAddWatch(fd, dir, syscall.IN_CLOSE_WRITE|syscall.IN_MOVED_TO|syscall.IN_DELETE|syscall.IN_MOVED_FROM|syscall.IN_MOVE_SELF|syscall.IN_DELETE_SELF)
			if err != nil {
				if !errors.Is(err, syscall.ENOENT) {
					return err
				}
				watched = nil
			} else {
				watched = current
				// A file written before the watch attached produces no event.
				read()
			}
		}
		// An ancestor rename leaves the watched inode alive without an event
		// on this directory. Check its pathname once a second while idle.
		if err := file.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
			return err
		}
		n, err := file.Read(buffer)
		if err != nil {
			if errors.Is(err, os.ErrDeadlineExceeded) || errors.Is(err, syscall.EINTR) {
				continue
			}
			return err
		}
		changed := false
		for offset := 0; offset+syscall.SizeofInotifyEvent <= n; {
			event := (*syscall.InotifyEvent)(unsafe.Pointer(&buffer[offset]))
			start := offset + syscall.SizeofInotifyEvent
			end := start + int(event.Len)
			if end > n {
				break
			}
			eventName := string(bytes.TrimRight(buffer[start:end], "\x00"))
			offset = end
			if int(event.Wd) == wd && event.Mask&syscall.IN_IGNORED != 0 {
				watched = nil
			}
			if (int(event.Wd) == wd && eventName == name) || event.Mask&syscall.IN_Q_OVERFLOW != 0 {
				changed = true
			}
		}
		if changed {
			read()
		}
	}
}
