package main

// Standard VIA boards use qmk_hid; Vial boards use VialRGB over raw HID.

import (
	"errors"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

const (
	qmkProvider          = "qmk"
	qmkEffectStatic      = 1
	qmkNoDeviceMarker    = "No device found"
	qmkDefaultDeviceName = "QMK keyboard"
	vialPayloadSize      = 32
	vialWireSize         = vialPayloadSize + 1
	vialSolidMode        = 2
)

var (
	qmkLookPath = func() bool { _, err := exec.LookPath("qmk_hid"); return err == nil }
	qmkList     = func() (string, error) {
		out, err := exec.Command("qmk_hid", "--list").CombinedOutput()
		return string(out), err
	}
	qmkRun             = func(args ...string) error { return exec.Command("qmk_hid", args...).Run() }
	qmkVialDevicePaths = findVialHIDPaths
	qmkSysfsRoot       = "/sys"
	qmkDeviceRoot      = "/dev"
)

func qmkInstalled() bool { return qmkLookPath() || len(qmkVialDevicePaths()) > 0 }

func qmkDevicePresent() bool {
	if len(qmkVialDevicePaths()) > 0 {
		return true
	}
	if !qmkLookPath() {
		return false
	}
	out, err := qmkList()
	if err != nil {
		return false
	}
	trimmed := strings.TrimSpace(out)
	return trimmed != "" && !strings.Contains(out, qmkNoDeviceMarker)
}

// readQMKDevices never touches the board on an ordinary state read; enumeration
// only runs from a scan or an apply, exactly like the other providers.
func readQMKDevices() ([]orgbDevice, error) {
	if !qmkDevicePresent() {
		return nil, nil
	}
	return []orgbDevice{qmkDeviceView()}, nil
}

func qmkDeviceView() orgbDevice {
	static := orgbMode{
		Name:      "Static",
		Value:     qmkEffectStatic,
		Flags:     modeHasModeColor | modeHasBrightness,
		BriMin:    0,
		BriMax:    100,
		ColorsMin: 1,
		ColorsMax: 1,
		Bri:       100,
		ColorMode: 2, // MODE_COLORS_MODE_SPECIFIC
		Colors:    []uint32{0xFFFFFF},
	}
	location := "qmk_hid"
	if len(qmkVialDevicePaths()) > 0 {
		location = "VialRGB"
	}
	return orgbDevice{
		Provider:    qmkProvider,
		Type:        "Keyboard",
		Name:        qmkDefaultDeviceName,
		Vendor:      "QMK",
		Description: "QMK/VIA keyboard",
		Serial:      qmkProvider + ":keyboard",
		Location:    location,
		ActiveMode:  0,
		Modes:       []orgbMode{static},
	}
}

func qmkApply(mode orgbMode, brightness int) error {
	hue, sat := 0, 0
	if len(mode.Colors) > 0 {
		r, g, b := unpackRGB(mode.Colors[0])
		h, s := rgbToHSV255(r, g, b)
		hue, sat = int(h), int(s)
	}
	bri := 100
	if brightness >= 0 {
		bri = clampPercent(brightness)
	}

	if paths := qmkVialDevicePaths(); len(paths) > 0 {
		var errs []error
		for _, path := range paths {
			if err := qmkWriteVial(path, byte(hue), byte(sat), bri); err != nil {
				errs = append(errs, err)
			}
		}
		return errors.Join(errs...)
	}
	return qmkWrite(int(mode.Value), hue, sat, bri)
}

func qmkWrite(effect, hue, sat, bri int) error {
	if err := qmkRun("via",
		"--rgb-effect", strconv.Itoa(effect),
		"--rgb-hue", strconv.Itoa(hue),
		"--rgb-saturation", strconv.Itoa(sat),
		"--rgb-brightness", strconv.Itoa(bri),
	); err != nil {
		return fmt.Errorf("qmk_hid: %w", err)
	}
	return nil
}

func findVialHIDPaths() []string {
	entries, _ := filepath.Glob(filepath.Join(qmkSysfsRoot, "class", "hidraw", "hidraw*"))
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		uevent, err := os.ReadFile(filepath.Join(entry, "device", "uevent"))
		if err != nil || !strings.HasPrefix(hidUeventValue(uevent, "HID_UNIQ"), "vial:") {
			continue
		}
		descriptor, err := os.ReadFile(filepath.Join(entry, "device", "report_descriptor"))
		if err != nil || !isVialRawInterface(descriptor) {
			continue
		}
		paths = append(paths, filepath.Join(qmkDeviceRoot, filepath.Base(entry)))
	}
	return paths
}

func hidUeventValue(data []byte, key string) string {
	prefix := key + "="
	for line := range strings.SplitSeq(string(data), "\n") {
		if strings.HasPrefix(line, prefix) {
			return strings.TrimPrefix(line, prefix)
		}
	}
	return ""
}

func isVialRawInterface(descriptor []byte) bool {
	var page, usagePage, usage uint32
	var haveUsage bool
	for i := 0; i < len(descriptor); {
		prefix := descriptor[i]
		if prefix == 0xfe {
			if i+2 >= len(descriptor) {
				return false
			}
			i += 3 + int(descriptor[i+1])
			continue
		}
		size := int(prefix & 3)
		if size == 3 {
			size = 4
		}
		if i+1+size > len(descriptor) {
			return false
		}
		var value uint32
		for j := range size {
			value |= uint32(descriptor[i+1+j]) << (8 * j)
		}
		itemType, tag := (prefix>>2)&3, prefix>>4
		switch {
		case itemType == 1 && tag == 0:
			page = value
		case itemType == 2 && tag == 0:
			usagePage, usage = page, value
			if size == 4 && value > 0xffff {
				usagePage, usage = value>>16, value&0xffff
			}
			haveUsage = true
		case itemType == 0 && tag == 10:
			if haveUsage && usagePage == 0xff60 && usage == 0x61 {
				return true
			}
			haveUsage = false
		case itemType == 0:
			haveUsage = false
		}
		i += 1 + size
	}
	return false
}

func qmkWriteVial(path string, hue, saturation byte, brightness int) error {
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	defer file.Close()
	if err := unix.SetNonblock(int(file.Fd()), true); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}

	var info [vialPayloadSize]byte
	info[0], info[1] = 0x08, 0x40
	if err := writeVialReport(file, info[:]); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	ready, err := unix.Poll([]unix.PollFd{{Fd: int32(file.Fd()), Events: unix.POLLIN}}, 500)
	if err != nil || ready == 0 {
		if err == nil {
			err = errors.New("VialRGB info timed out")
		}
		return fmt.Errorf("%s: %w", path, err)
	}
	n, err := unix.Read(int(file.Fd()), info[:])
	if err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	if n < 5 || info[0] != 0x08 || info[1] != 0x40 || info[4] == 0 {
		return fmt.Errorf("%s: invalid VialRGB info response", path)
	}

	value := byte((clampPercent(brightness)*int(info[4]) + 50) / 100)
	var report [vialPayloadSize]byte
	report[0], report[1] = 0x07, 0x41
	report[2], report[3] = byte(vialSolidMode), byte(vialSolidMode>>8)
	report[4], report[5], report[6], report[7] = 0, hue, saturation, value
	if err := writeVialReport(file, report[:]); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}

func writeVialReport(file *os.File, report []byte) error {
	var wire [vialWireSize]byte
	copy(wire[1:], report)
	n, err := file.Write(wire[:])
	if err != nil {
		return err
	}
	if n != len(wire) {
		return fmt.Errorf("short VialRGB write: %d of %d bytes", n, len(wire))
	}
	return nil
}

// rgbToHSV255 mirrors Python colorsys.rgb_to_hsv scaled to the 0-255 range VIA
// uses (what omarchy's Framework 16 script computes), returning hue and
// saturation; value/brightness is carried separately as a percentage.
func rgbToHSV255(rf, gf, bf float64) (uint8, uint8) {
	maxc := math.Max(rf, math.Max(gf, bf))
	minc := math.Min(rf, math.Min(gf, bf))
	if maxc == minc {
		return 0, 0
	}
	delta := maxc - minc
	sat := delta / maxc
	rc := (maxc - rf) / delta
	gc := (maxc - gf) / delta
	bc := (maxc - bf) / delta
	var h float64
	switch maxc {
	case rf:
		h = bc - gc
	case gf:
		h = 2 + rc - bc
	default:
		h = 4 + gc - rc
	}
	h = math.Mod(h/6, 1)
	if h < 0 {
		h++
	}
	return uint8(h * 255), uint8(sat * 255)
}
