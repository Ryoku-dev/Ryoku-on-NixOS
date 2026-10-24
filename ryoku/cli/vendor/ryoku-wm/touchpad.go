package wm

import (
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// TouchpadEcho is how close two touchpad-toggle presses must land to count as
// one. Several laptops report the FN touchpad key on two input devices at once
// (ASUS: hid-asus sends KEY_F21 and asus-wmi sends KEY_TOUCHPAD_TOGGLE, and xkb
// maps both to XF86TouchpadToggle), so one press arrives as two toggles and the
// pad flips off and straight back on. No person toggles the pad twice inside
// this window, so a second toggle in it is the echo and is dropped.
const TouchpadEcho = 700 * time.Millisecond

// touchpadStampPath is where the last accepted toggle is stamped. The runtime
// dir is per login and cleared on reboot, which is exactly the stamp's life.
var touchpadStampPath = func() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "ryoku-touchpad-toggle")
}

// TouchpadToggleIsEcho reports whether a toggle arriving now is the second half
// of a double-reported key press, and stamps it when it is not. The two halves
// spawn two processes within milliseconds, so the check and the stamp happen
// under one lock. Providers call it before flipping the pad on a toggle; on and
// off are idempotent and never need it.
func TouchpadToggleIsEcho(now time.Time) bool {
	f, err := os.OpenFile(touchpadStampPath(), os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return false
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err == nil {
		defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	}
	if st, err := f.Stat(); err == nil && st.Size() > 0 {
		if d := now.Sub(st.ModTime()); d >= 0 && d < TouchpadEcho {
			return true
		}
	}
	if _, err := f.WriteAt([]byte{'1'}, 0); err == nil {
		_ = os.Chtimes(f.Name(), now, now)
	}
	return false
}
