package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/godbus/dbus/v5"
)

// powersounds watches the system battery and AC line over sysfs and plays the
// battery-low, battery-full, plug, and unplug cues. It reads /sys/class/power_supply directly
// rather than depend on a running UPower. A machine with no battery or no mains
// simply never fires those cues.

const powerSupplyRoot = "/sys/class/power_supply"

// batteryLowPercent is the critical threshold: at or below 3 (strictly under 4)
// the discharging-battery cue fires. batteryLowRepeat is how often it repeats
// while the machine stays in that state.
const (
	batteryLowPercent = 4
	batteryLowRepeat  = 60 * time.Second
	powerReconcile    = 5 * time.Minute
)

// powerState is the sysfs snapshot the cues key off. The battery fields describe
// the system battery only; peripheral batteries are excluded when it is read.
type powerState struct {
	haveAC      bool // a Mains supply exists
	online      bool // AC is plugged in
	present     bool // the system battery is present
	discharging bool // the system battery status is Discharging
	full        bool // the system battery status is Full
	percent     int  // system battery capacity 0..100
}

// readPowerState scans the power-supply class for the mains and system battery.
func readPowerState() powerState { return readPowerStateFrom(powerSupplyRoot) }

// readPowerStateFrom is readPowerState with an injectable root so the device
// selection is testable without real sysfs. Missing attributes leave their
// fields zero, which the cue guards treat as "no cue".
func readPowerStateFrom(root string) powerState {
	var st powerState
	entries, err := os.ReadDir(root)
	if err != nil {
		return st
	}
	for _, e := range entries {
		base := filepath.Join(root, e.Name())
		switch readTrim(filepath.Join(base, "type")) {
		case "Mains":
			st.haveAC = true
			if readTrim(filepath.Join(base, "online")) == "1" {
				st.online = true
			}
		case "Battery":
			// Peripheral batteries (mouse, keyboard, headset) report scope
			// "Device"; only the system battery drives the low-battery cue, so a
			// depleted peripheral never fires the chime while the laptop is fine.
			if strings.EqualFold(readTrim(filepath.Join(base, "scope")), "Device") {
				continue
			}
			if readTrim(filepath.Join(base, "present")) == "1" {
				st.present = true
			}
			switch strings.ToLower(readTrim(filepath.Join(base, "status"))) {
			case "discharging":
				st.discharging = true
			case "full":
				st.full = true
			}
			if n, err := strconv.Atoi(readTrim(filepath.Join(base, "capacity"))); err == nil {
				st.percent = n
			}
		}
	}
	return st
}

// watchPowerSounds fires the battery-low, battery-full, plug, and unplug cues off
// sysfs.
//
// Plug/unplug: the very first AC reading only seeds the baseline so no cue fires
// at login for the state the machine booted in; thereafter every online change
// plays plug (on) or unplug (off).
//
// Battery low: while the system battery is present, discharging, and under 4
// percent, the cue plays at once on entering the state and then every 60 s until
// it leaves. Leaving the state (charging, plugged, or risen above the threshold)
// re-arms the immediate play for the next time it drops.
//
// Battery full: plays once when the plugged-in battery reaches Full. Like AC,
// the first reading only seeds it, so a machine that boots full stays quiet.
type powerCue struct {
	acSeen    bool
	lastAC    bool
	lowActive bool
	lastLow   time.Time
	fullSeen  bool
	lastFull  bool
}

// step folds one sysfs snapshot into the tracker and returns the cues to play.
// It is pure over its receiver and now, so the skip-first-AC and battery-low
// immediate-then-repeat rules are unit-testable without sysfs or a clock.
func (c *powerCue) step(st powerState, now time.Time) []string {
	var cues []string
	if st.haveAC {
		if !c.acSeen {
			c.acSeen = true
			c.lastAC = st.online
		} else if st.online != c.lastAC {
			c.lastAC = st.online
			if st.online {
				cues = append(cues, soundPowerPlug)
			} else {
				cues = append(cues, soundPowerUnplug)
			}
		}
	}

	if st.present {
		full := st.full && (st.online || !st.haveAC)
		if !c.fullSeen {
			c.fullSeen = true
		} else if full && !c.lastFull {
			cues = append(cues, soundBatteryFull)
		}
		c.lastFull = full
	}

	low := st.present && st.discharging && st.percent < batteryLowPercent
	if low {
		if !c.lowActive || now.Sub(c.lastLow) >= batteryLowRepeat {
			cues = append(cues, soundBatteryLow)
			c.lastLow = now
		}
		c.lowActive = true
	} else {
		c.lowActive = false
	}
	return cues
}

func powerCueWait(c powerCue, busEvents, usbEvents, deviceCues bool, now time.Time) time.Duration {
	if c.lowActive {
		wait := batteryLowRepeat - now.Sub(c.lastLow)
		if wait < time.Second {
			return time.Second
		}
		if wait < powerReconcile {
			return wait
		}
	}
	if !busEvents || (deviceCues && !usbEvents) {
		return powerReconcile
	}
	return 0
}

func (d *daemon) watchPowerSounds() {
	var c powerCue
	var dc deviceCue

	var conn *dbus.Conn
	var signals chan *dbus.Signal
	if candidate, err := dbus.ConnectSystemBus(); err == nil {
		if addUPowerSignalMatch(candidate) == nil {
			conn = candidate
			signals = make(chan *dbus.Signal, 16)
			conn.Signal(signals)
		} else {
			_ = candidate.Close()
		}
	}
	if conn != nil {
		defer conn.Close()
		defer conn.RemoveSignal(signals)
	}
	var busLost <-chan struct{}
	if conn != nil {
		busLost = conn.Context().Done()
	}

	usbChanges, stopUSBWatch, usbErr := watchUSBChanges(usbDevicesRoot)
	if usbErr == nil {
		defer stopUSBWatch()
	} else {
		usbChanges = nil
	}

	timer := time.NewTimer(time.Hour)
	if !timer.Stop() {
		<-timer.C
	}
	defer timer.Stop()
	var timerC <-chan time.Time
	for {
		now := time.Now()
		for _, cue := range c.step(readPowerState(), now) {
			d.playSound(cue)
		}
		ev := d.soundPrefs().Events
		deviceCues := ev.DeviceAdded.Enabled || ev.DeviceRemoved.Enabled
		if deviceCues {
			for _, cue := range dc.stepWithSuspend(usbDevices(usbDevicesRoot), systemSuspendOffset()) {
				d.playSound(cue)
			}
		} else {
			dc = deviceCue{}
		}

		wait := powerCueWait(c, signals != nil, usbChanges != nil, deviceCues, now)
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		timerC = nil
		if wait > 0 {
			timer.Reset(wait)
			timerC = timer.C
		}

	wait:
		select {
		case <-d.quit:
			return
		case <-busLost:
			busLost = nil
			signals = nil
		case sig, ok := <-signals:
			if !ok {
				signals = nil
				break
			}
			if !powerStateSignal(sig) {
				goto wait
			}
		case _, ok := <-usbChanges:
			if !ok {
				usbChanges = nil
			}
		case <-timerC:
		}
	}
}
