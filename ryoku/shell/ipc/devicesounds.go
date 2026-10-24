package main

import (
	"bytes"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/unix"
)

// devicesounds plays the device-added and device-removed cues from kernel USB
// uevents. The sysfs list is read only after a real device edge.

const usbDevicesRoot = "/sys/bus/usb/devices"

// watchUSBChanges listens to kernel uevents, so device cues do not need a
// directory poll. Closing the netlink socket stops its blocking receive.
func watchUSBChanges(_ string) (<-chan struct{}, func(), error) {
	fd, err := unix.Socket(
		unix.AF_NETLINK,
		unix.SOCK_DGRAM|unix.SOCK_CLOEXEC,
		unix.NETLINK_KOBJECT_UEVENT,
	)
	if err != nil {
		return nil, nil, err
	}
	if err := unix.Bind(fd, &unix.SockaddrNetlink{
		Family: unix.AF_NETLINK,
		Groups: 1,
	}); err != nil {
		unix.Close(fd)
		return nil, nil, err
	}
	changes := make(chan struct{}, 1)
	var once sync.Once
	stop := func() {
		once.Do(func() {
			_ = unix.Close(fd)
		})
	}
	go func() {
		defer close(changes)
		buf := make([]byte, 16*1024)
		for {
			n, _, err := unix.Recvfrom(fd, buf, 0)
			if err != nil {
				return
			}
			action, subsystem := "", ""
			for _, field := range bytes.Split(buf[:n], []byte{0}) {
				switch {
				case bytes.HasPrefix(field, []byte("ACTION=")):
					action = string(field[len("ACTION="):])
				case bytes.HasPrefix(field, []byte("SUBSYSTEM=")):
					subsystem = string(field[len("SUBSYSTEM="):])
				}
			}
			if subsystem != "usb" || (action != "add" && action != "remove") {
				continue
			}
			select {
			case changes <- struct{}{}:
			default:
			}
		}
	}()
	return changes, stop, nil
}

// usbDevices names the attached USB devices: entries like "1-2" or "3-1.4".
// Interfaces ("1-2:1.0") and the root hubs ("usb1") are left out, so one plug
// is one name.
func usbDevices(root string) map[string]bool {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	out := make(map[string]bool, len(entries))
	for _, e := range entries {
		n := e.Name()
		if strings.HasPrefix(n, "usb") || strings.Contains(n, ":") {
			continue
		}
		out[n] = true
	}
	return out
}

// deviceCue tracks the attached set between events. The first reading only
// seeds it. A suspend-clock jump reseeds it too, because resume re-enumeration
// is not something the user plugged.
type deviceCue struct {
	seen          bool
	last          map[string]bool
	suspendOffset time.Duration
}

func (c *deviceCue) stepWithSuspend(now map[string]bool, suspendOffset time.Duration) []string {
	reseed := !c.seen || suspendOffset-c.suspendOffset > 20*time.Millisecond
	c.suspendOffset = suspendOffset
	return c.stepNow(now, reseed)
}

func (c *deviceCue) stepNow(now map[string]bool, reseed bool) []string {
	if now == nil {
		return nil
	}
	prev := c.last
	c.seen, c.last = true, now
	if reseed {
		return nil
	}
	var cues []string
	for n := range now {
		if !prev[n] {
			cues = append(cues, soundDeviceAdded)
			break
		}
	}
	for n := range prev {
		if !now[n] {
			cues = append(cues, soundDeviceRemoved)
			break
		}
	}
	return cues
}
