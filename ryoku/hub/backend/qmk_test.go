package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// rgbToHSV255 must match Python colorsys.rgb_to_hsv scaled to 0-255 and
// truncated, since that is the reference omarchy's Framework 16 script uses.
func TestRGBToHSV255MatchesColorsys(t *testing.T) {
	cases := []struct {
		name             string
		r, g, b          float64
		wantHue, wantSat uint8
	}{
		{"red", 1, 0, 0, 0, 255},
		{"green", 0, 1, 0, 85, 255},
		{"blue", 0, 0, 1, 170, 255},
		{"cyan", 0, 1, 1, 127, 255},
		{"white", 1, 1, 1, 0, 0},
		{"black", 0, 0, 0, 0, 0},
	}
	for _, c := range cases {
		hue, sat := rgbToHSV255(c.r, c.g, c.b)
		if hue != c.wantHue || sat != c.wantSat {
			t.Errorf("%s: got hue=%d sat=%d, want hue=%d sat=%d", c.name, hue, sat, c.wantHue, c.wantSat)
		}
	}
}

func TestQmkDevicePresent(t *testing.T) {
	stubNoVial(t)
	defer restoreQmkSeams(qmkLookPath, qmkList, qmkRun)
	qmkLookPath = func() bool { return true }

	qmkList = func() (string, error) { return "No device found\n", nil }
	if qmkDevicePresent() {
		t.Error("the no-device marker must read as absent")
	}
	qmkList = func() (string, error) { return "", nil }
	if qmkDevicePresent() {
		t.Error("empty output must read as absent")
	}
	qmkList = func() (string, error) { return "", errors.New("permission denied") }
	if qmkDevicePresent() {
		t.Error("an enumeration error must read as absent")
	}
	qmkList = func() (string, error) {
		return "32ac:0014  Framework  Laptop 16 Keyboard  0.1.0  FRAK000\n", nil
	}
	if !qmkDevicePresent() {
		t.Error("a listed device must read as present")
	}

	qmkLookPath = func() bool { return false }
	if qmkDevicePresent() {
		t.Error("without qmk_hid the provider must read as absent")
	}
}

func TestReadQMKDevicesAbsentIsQuiet(t *testing.T) {
	stubNoVial(t)
	defer restoreQmkSeams(qmkLookPath, qmkList, qmkRun)
	qmkLookPath = func() bool { return false }
	devices, err := readQMKDevices()
	if err != nil {
		t.Fatalf("absence must not be an error: %v", err)
	}
	if devices != nil {
		t.Fatalf("no device expected, got %+v", devices)
	}
}

func TestQmkDeviceIdentityAndRouting(t *testing.T) {
	stubNoVial(t)
	d := qmkDeviceView()
	if d.Provider != qmkProvider || d.Type != "Keyboard" {
		t.Fatalf("device = %+v", d)
	}
	if len(d.Modes) != 1 || d.Modes[0].Name != "Static" || d.Modes[0].Value != qmkEffectStatic {
		t.Fatalf("modes = %+v", d.Modes)
	}
	key := deviceKey(d)
	if key != "QMK keyboard#qmk:keyboard" {
		t.Fatalf("key = %q", key)
	}
	if providersForKey(key) != lightingQMK {
		t.Fatalf("providersForKey(%q) routed to the wrong provider", key)
	}
}

// applyOne must drive a QMK device through qmk_hid without an OpenRGB connection,
// converting the accent to the hue/saturation the VIA protocol wants.
func TestApplyOneRoutesQMKToHidWrite(t *testing.T) {
	stubNoVial(t)
	defer restoreQmkSeams(qmkLookPath, qmkList, qmkRun)
	var got []string
	qmkRun = func(args ...string) error { got = args; return nil }

	live := []orgbDevice{qmkDeviceView()}
	s := &lightingSettings{Managed: true, Mode: "Static", Source: "accent", Brightness: -1, Speed: -1}
	if err := applyOne(nil, live, deviceKey(live[0]), s, "#00FF00"); err != nil {
		t.Fatalf("applyOne: %v", err)
	}
	// green accent -> hue 85, full saturation; device-own brightness (-1) -> 100%.
	want := []string{"via", "--rgb-effect", "1", "--rgb-hue", "85", "--rgb-saturation", "255", "--rgb-brightness", "100"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("qmk_hid args = %v, want %v", got, want)
	}
}

func TestQmkApplyHonoursBrightness(t *testing.T) {
	stubNoVial(t)
	defer restoreQmkSeams(qmkLookPath, qmkList, qmkRun)
	var got []string
	qmkRun = func(args ...string) error { got = args; return nil }

	mode := orgbMode{Name: "Static", Value: qmkEffectStatic, Colors: []uint32{0xFF0000}} // blue packed (red low byte)
	if err := qmkApply(mode, 40); err != nil {
		t.Fatalf("qmkApply: %v", err)
	}
	want := []string{"via", "--rgb-effect", "1", "--rgb-hue", "170", "--rgb-saturation", "255", "--rgb-brightness", "40"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("qmk_hid args = %v, want %v", got, want)
	}
}

func TestQmkApplyWritesExactVialRGBReports(t *testing.T) {
	oldPaths, oldRun := qmkVialDevicePaths, qmkRun
	t.Cleanup(func() { qmkVialDevicePaths, qmkRun = oldPaths, oldRun })

	path := filepath.Join(t.TempDir(), "hidraw0")
	fixture := make([]byte, vialWireSize+vialPayloadSize)
	fixture[vialWireSize], fixture[vialWireSize+1], fixture[vialWireSize+4] = 0x08, 0x40, 200
	if err := os.WriteFile(path, fixture, 0o600); err != nil {
		t.Fatal(err)
	}
	qmkVialDevicePaths = func() []string { return []string{path} }
	qmkRun = func(...string) error {
		t.Fatal("Vial board fell through to qmk_hid")
		return nil
	}

	mode := orgbMode{Name: "Static", Value: qmkEffectStatic, Colors: []uint32{0x00FF00}}
	if err := qmkApply(mode, 50); err != nil {
		t.Fatalf("qmkApply: %v", err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	wantSize := vialWireSize*2 + vialPayloadSize
	if len(got) != wantSize {
		t.Fatalf("fake hidraw size = %d, want %d", len(got), wantSize)
	}
	var wantInfo [vialWireSize]byte
	wantInfo[1], wantInfo[2] = 0x08, 0x40
	var wantSet [vialWireSize]byte
	wantSet[1], wantSet[2], wantSet[3] = 0x07, 0x41, 0x02
	wantSet[6], wantSet[7], wantSet[8] = 85, 255, 100
	if !reflect.DeepEqual(got[:vialWireSize], wantInfo[:]) {
		t.Fatalf("VialRGB info report = %v, want %v", got[:vialWireSize], wantInfo)
	}
	setOffset := vialWireSize + vialPayloadSize
	if !reflect.DeepEqual(got[setOffset:], wantSet[:]) {
		t.Fatalf("VialRGB set report = %v, want %v", got[setOffset:], wantSet)
	}
}

func TestFindVialHIDPathsRequiresSerialAndRawUsage(t *testing.T) {
	oldSysfs, oldDevices := qmkSysfsRoot, qmkDeviceRoot
	t.Cleanup(func() { qmkSysfsRoot, qmkDeviceRoot = oldSysfs, oldDevices })
	root := t.TempDir()
	qmkSysfsRoot = filepath.Join(root, "sys")
	qmkDeviceRoot = filepath.Join(root, "dev")

	makeDevice := func(name, serial string, descriptor []byte) {
		t.Helper()
		device := filepath.Join(qmkSysfsRoot, "class", "hidraw", name, "device")
		if err := os.MkdirAll(device, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(device, "uevent"), []byte("HID_UNIQ="+serial+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(device, "report_descriptor"), descriptor, 0o600); err != nil {
			t.Fatal(err)
		}
	}
	raw := []byte{0x06, 0x60, 0xff, 0x09, 0x61, 0xa1, 0x01, 0xc0}
	makeDevice("hidraw0", "vial:f64c2b3c", raw)
	makeDevice("hidraw1", "ordinary", raw)
	makeDevice("hidraw2", "vial:not-raw", []byte{0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0xc0})

	want := []string{filepath.Join(qmkDeviceRoot, "hidraw0")}
	if got := findVialHIDPaths(); !reflect.DeepEqual(got, want) {
		t.Fatalf("Vial hidraw paths = %v, want %v", got, want)
	}
}

// A QMK keyboard coexists with the other providers' devices in one report.
func TestQmkKeyboardJoinsLightingDevices(t *testing.T) {
	stubNoVial(t)
	mb := orgbDevice{Name: "Desktop", Type: "Motherboard", Serial: "mb"}
	live := append(combineLightingDevices([]orgbDevice{mb}, nil), qmkDeviceView())
	if len(live) != 2 {
		t.Fatalf("devices = %d, want motherboard and QMK keyboard", len(live))
	}
	if live[1].Provider != qmkProvider || live[1].Type != "Keyboard" {
		t.Fatalf("devices = %+v", live)
	}
}

func stubNoVial(t *testing.T) {
	t.Helper()
	old := qmkVialDevicePaths
	qmkVialDevicePaths = func() []string { return nil }
	t.Cleanup(func() { qmkVialDevicePaths = old })
}

func restoreQmkSeams(look func() bool, list func() (string, error), run func(...string) error) {
	qmkLookPath = look
	qmkList = list
	qmkRun = run
}
