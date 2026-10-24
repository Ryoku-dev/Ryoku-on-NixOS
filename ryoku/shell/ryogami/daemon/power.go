package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const powerFallbackPollInterval = time.Minute

// A variable so a test can point it at a fixture tree.
var powerSupplyRoot = "/sys/class/power_supply"

// Peripheral batteries (scope Device) are skipped: only the machine's own counts.
func parsePowerState(root string) (onBattery, present bool, percent int, havePercent bool) {
	ents, err := os.ReadDir(root)
	if err != nil {
		return
	}
	for _, e := range ents {
		dir := filepath.Join(root, e.Name())
		if !strings.EqualFold(readTrimmed(filepath.Join(dir, "type")), "Battery") {
			continue
		}
		if strings.EqualFold(readTrimmed(filepath.Join(dir, "scope")), "Device") {
			continue
		}
		present = true
		if strings.EqualFold(readTrimmed(filepath.Join(dir, "status")), "Discharging") {
			onBattery = true
		}
		if !havePercent {
			if c, err := strconv.Atoi(readTrimmed(filepath.Join(dir, "capacity"))); err == nil {
				percent, havePercent = c, true
			}
		}
	}
	return
}

func readTrimmed(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func powerOnBattery() bool {
	on, _, _, _ := parsePowerState(powerSupplyRoot)
	return on
}

func batteryPresent() bool {
	_, present, _, _ := parsePowerState(powerSupplyRoot)
	return present
}

func batteryPercent() (int, bool) {
	_, present, pct, have := parsePowerState(powerSupplyRoot)
	return pct, present && have
}

func (d *daemon) pickerGpuEnv() []string {
	if os.Getenv("DRI_PRIME") != "" {
		return nil
	}
	pref := d.settingString("performance.gpuPreference")
	if pref == "auto" {
		if d.batterySaverActive() {
			pref = "low"
		} else {
			return nil
		}
	}
	switch pref {
	case "high":
		// DRI_PRIME only steers Mesa; the NVIDIA driver takes its own offload switches.
		if fileExists("/proc/driver/nvidia/version") {
			return []string{"__NV_PRIME_RENDER_OFFLOAD=1", "__VK_LAYER_NV_optimus=NVIDIA_only", "__GLX_VENDOR_LIBRARY_NAME=nvidia"}
		}
		return []string{"DRI_PRIME=1"}
	case "low":
		return []string{"DRI_PRIME=0"}
	}
	return nil
}

var powerSupplyUevent = []byte("\x00SUBSYSTEM=power_supply\x00")

func openPowerEventSocket() (int, error) {
	fd, err := syscall.Socket(syscall.AF_NETLINK, syscall.SOCK_DGRAM|syscall.SOCK_CLOEXEC, syscall.NETLINK_KOBJECT_UEVENT)
	if err != nil {
		return -1, err
	}
	addr := &syscall.SockaddrNetlink{Family: syscall.AF_NETLINK, Groups: 1}
	if err := syscall.Bind(fd, addr); err != nil {
		syscall.Close(fd)
		return -1, err
	}
	return fd, nil
}

func runPowerEvents(fd int, changed func()) error {
	return runPowerEventReader(func(buf []byte) (int, error) {
		return syscall.Read(fd, buf)
	}, changed)
}

func runPowerEventReader(readEvent func([]byte) (int, error), changed func()) error {
	buf := make([]byte, 16*1024)
	for {
		n, err := readEvent(buf)
		if err == syscall.EINTR {
			continue
		}
		if err == syscall.ENOBUFS {
			changed()
			continue
		}
		if err != nil {
			return err
		}
		if n > 0 && bytes.Contains(buf[:n], powerSupplyUevent) {
			changed()
		}
	}
}

func (d *daemon) watchPower() {
	last := powerOnBattery()
	d.broadcastPower(last)
	changed := func() {
		now := powerOnBattery()
		if now == last {
			return
		}
		last = now
		d.broadcastPower(now)
		d.reevaluatePause()
	}
	fd, err := openPowerEventSocket()
	if err == nil {
		err = runPowerEvents(fd, changed)
		syscall.Close(fd)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "ryogami: power event watch unavailable, polling every %s: %v\n", powerFallbackPollInterval, err)
	}
	ticker := time.NewTicker(powerFallbackPollInterval)
	defer ticker.Stop()
	for range ticker.C {
		changed()
	}
}

func (d *daemon) broadcastPower(onBattery bool) {
	d.broadcast("ryogami.power.changed", d.powerStatus(onBattery))
}

// powerStatus is what the settings page shows: the supply, and whether the battery limits apply.
func (d *daemon) powerStatus(onBattery bool) map[string]interface{} {
	data := map[string]interface{}{
		"onBattery":   onBattery,
		"present":     batteryPresent(),
		"saverActive": onBattery && d.settingBool("performance.batterySaver"),
	}
	if pct, havePct := batteryPercent(); havePct {
		data["percent"] = pct
	}
	return data
}

func init() {
	registerAvailability("battery", func(d *daemon) bool { return batteryPresent() })
	onStart(func(d *daemon) { go d.watchPower() })
}
