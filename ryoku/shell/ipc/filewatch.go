package main

import (
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/unix"
)

// Watch the parent because shell and Hub saves replace the file by rename.
func (d *daemon) watchFile(path string, onChange func()) {
	var last time.Time
	check := func() {
		fi, err := os.Stat(path)
		if err != nil {
			return
		}
		if m := fi.ModTime(); !m.Equal(last) {
			changed := !last.IsZero()
			last = m
			if changed {
				onChange()
			}
		}
	}
	check()

	fd, err := unix.InotifyInit1(unix.IN_CLOEXEC | unix.IN_NONBLOCK)
	if err == nil {
		if _, watchErr := unix.InotifyAddWatch(fd, filepath.Dir(path),
			unix.IN_CLOSE_WRITE|unix.IN_CREATE|unix.IN_MOVED_TO); watchErr != nil {
			unix.Close(fd)
			fd = -1
		}
	}
	if err != nil {
		fd = -1
	}
	if fd >= 0 {
		defer unix.Close(fd)
	}
	buf := make([]byte, 4096)
	for {
		if fd >= 0 {
			pfds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN | unix.POLLERR}}
			_, _ = unix.Poll(pfds, int((5*time.Minute)/time.Millisecond))
			for pfds[0].Revents != 0 {
				if _, err := unix.Read(fd, buf); err != nil {
					break
				}
			}
		} else {
			timer := time.NewTimer(30 * time.Second)
			select {
			case <-d.quit:
				timer.Stop()
				return
			case <-timer.C:
			}
		}
		select {
		case <-d.quit:
			return
		default:
		}
		check()
	}
}
