package main

import (
	"testing"

	"github.com/godbus/dbus/v5"
)

// TestAutoProfileStep walks one tracker through a full battery lifecycle: the
// switch on unplug, no re-switch mid-episode, a manual override left alone, and
// the restore on AC only when the profile is still the saver we set.
func TestAutoProfileStep(t *testing.T) {
	saver := []string{"performance", "balanced", "power-saver"}
	seq := []struct {
		name      string
		enabled   bool
		onBattery bool
		current   string
		avail     []string
		want      string
	}{
		{"boot on AC: no switch", true, false, "balanced", saver, ""},
		{"unplug: switch to saver, save balanced", true, true, "balanced", saver, "power-saver"},
		{"still on battery: no re-switch", true, true, "power-saver", saver, ""},
		{"manual perf on battery: left alone", true, true, "performance", saver, ""},
		{"plug in after manual change: do not restore", true, false, "performance", saver, ""},
		{"unplug again: switch, save balanced", true, true, "balanced", saver, "power-saver"},
		{"plug in, still saver: restore balanced", true, false, "power-saver", saver, "balanced"},
		{"on AC idle: nothing", true, false, "balanced", saver, ""},
	}
	a := &autoProfile{}
	for _, s := range seq {
		if got := a.step(s.enabled, s.onBattery, s.current, s.avail); got != s.want {
			t.Errorf("%s: step = %q, want %q", s.name, got, s.want)
		}
	}
}

// TestAutoProfileGuards: turning the feature off while on battery undoes the
// switch, and a machine without a power-saver profile or with the feature off
// never switches.
func TestAutoProfileGuards(t *testing.T) {
	saver := []string{"balanced", "power-saver"}

	off := &autoProfile{}
	if got := off.step(true, true, "balanced", saver); got != "power-saver" {
		t.Fatalf("enable on battery: got %q, want power-saver", got)
	}
	if got := off.step(false, true, "power-saver", saver); got != "balanced" {
		t.Errorf("disable while on battery: got %q, want balanced (restore)", got)
	}

	noSaver := &autoProfile{}
	if got := noSaver.step(true, true, "balanced", []string{"balanced", "performance"}); got != "" {
		t.Errorf("no power-saver profile: got %q, want no-op", got)
	}

	disabled := &autoProfile{}
	if got := disabled.step(false, true, "balanced", saver); got != "" {
		t.Errorf("feature off: got %q, want no-op", got)
	}
}

func TestPowerStateSignal(t *testing.T) {
	cases := []struct {
		name string
		sig  *dbus.Signal
		want bool
	}{
		{"power profile property", &dbus.Signal{Name: propertiesInterface + ".PropertiesChanged", Path: dbus.ObjectPath(ppPath)}, true},
		{"UPower root property", &dbus.Signal{Name: propertiesInterface + ".PropertiesChanged", Path: upowerPath}, true},
		{"battery property", &dbus.Signal{Name: propertiesInterface + ".PropertiesChanged", Path: "/org/freedesktop/UPower/devices/battery_BAT0"}, true},
		{"device added", &dbus.Signal{Name: "org.freedesktop.UPower.DeviceAdded", Path: upowerPath}, true},
		{"unrelated path", &dbus.Signal{Name: propertiesInterface + ".PropertiesChanged", Path: "/org/example"}, false},
		{"unrelated member", &dbus.Signal{Name: "org.freedesktop.UPower.Sleeping", Path: upowerPath}, false},
		{"nil", nil, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := powerStateSignal(tc.sig); got != tc.want {
				t.Fatalf("powerStateSignal = %v, want %v", got, tc.want)
			}
		})
	}
}
