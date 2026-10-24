package main

import (
	"encoding/binary"
	"strings"
	"sync"

	"golang.org/x/sys/unix"
)

type fileEvent struct {
	watch int32
	mask  uint32
	name  string
}

func decodeFileEvents(buf []byte) []fileEvent {
	events := make([]fileEvent, 0, 4)
	for len(buf) >= unix.SizeofInotifyEvent {
		nameLen := int(binary.NativeEndian.Uint32(buf[12:16]))
		size := unix.SizeofInotifyEvent + nameLen
		if size > len(buf) {
			break
		}
		name := strings.TrimRight(string(buf[unix.SizeofInotifyEvent:size]), "\x00")
		events = append(events, fileEvent{
			watch: int32(binary.NativeEndian.Uint32(buf[0:4])),
			mask:  binary.NativeEndian.Uint32(buf[4:8]),
			name:  name,
		})
		buf = buf[size:]
	}
	return events
}

func signalEventFD(fd int) {
	var value [8]byte
	binary.NativeEndian.PutUint64(value[:], 1)
	_, _ = unix.Write(fd, value[:])
}

func quitEventFD(quit <-chan struct{}) (int, func(), error) {
	fd, err := unix.Eventfd(0, unix.EFD_CLOEXEC|unix.EFD_NONBLOCK)
	if err != nil {
		return -1, nil, err
	}
	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		select {
		case <-quit:
			signalEventFD(fd)
		case <-stop:
		}
	}()
	var once sync.Once
	cancel := func() {
		once.Do(func() { close(stop) })
		<-done
	}
	return fd, cancel, nil
}
