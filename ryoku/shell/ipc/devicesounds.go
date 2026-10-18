package main

import (
	"os"
	"strings"
	"time"
)

// devicesounds plays the device-added and device-removed cues when a USB device
// is plugged in or pulled out. It lists /sys/bus/usb/devices on the power-sound
// poll rather than hold a udev socket, so it costs one directory read every two
// seconds and needs no extra library.

const usbDevicesRoot = "/sys/bus/usb/devices"

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

// deviceCue tracks the attached set between polls. The first reading only seeds
// it, and a gap far longer than the poll (a suspend) reseeds it too, because a
// resume re-enumerates every device and is not something the user plugged.
type deviceCue struct {
	seen  bool
	last  map[string]bool
	stamp time.Time
}

func (c *deviceCue) step(now map[string]bool, at time.Time) []string {
	if now == nil {
		return nil
	}
	reseed := !c.seen || at.Sub(c.stamp) > 3*powerPoll
	prev := c.last
	c.seen, c.last, c.stamp = true, now, at
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
