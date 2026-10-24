package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// sounds plays the event cues the shell owns: notifications, power plug and
// unplug, low and full battery, devices coming and going, the screenshot shutter
// and output volume changes. The built-in clips are OGA files from the
// freedesktop sound theme, embedded in the daemon so playback needs no install
// path. The `sounds` key in shell.json turns cues on or off one by one, swaps any
// cue for the user's own file and sets one volume for all of them. Every failure
// mode is silent: a missing player, an unwritable cache or a vanished custom file
// falls back or drops the cue rather than disturbing the caller.

//go:embed assets/*.oga
var soundAssets embed.FS

const (
	soundNotification         = "notification"
	soundNotificationCritical = "notification-critical"
	soundPowerPlug            = "power-plug"
	soundPowerUnplug          = "power-unplug"
	soundBatteryLow           = "battery-low"
	soundBatteryFull          = "battery-full"
	soundDeviceAdded          = "device-added"
	soundDeviceRemoved        = "device-removed"
	soundShutter              = "shutter"
	soundVolumeChange         = "volume-change"
)

// soundEvent is one cue's setting: whether it plays, and the user's own file to
// play instead of the built-in clip (empty for the built-in).
type soundEvent struct {
	Enabled bool   `json:"enabled"`
	File    string `json:"file"`
}

// soundEvents names every cue as its own field, so a partial object on disk
// keeps the defaults of the fields it leaves out and a patch to an unknown cue
// is rejected like any other unknown setting.
type soundEvents struct {
	Notification         soundEvent `json:"notification"`
	NotificationCritical soundEvent `json:"notification-critical"`
	PowerPlug            soundEvent `json:"power-plug"`
	PowerUnplug          soundEvent `json:"power-unplug"`
	BatteryLow           soundEvent `json:"battery-low"`
	BatteryFull          soundEvent `json:"battery-full"`
	DeviceAdded          soundEvent `json:"device-added"`
	DeviceRemoved        soundEvent `json:"device-removed"`
	Shutter              soundEvent `json:"shutter"`
	VolumeChange         soundEvent `json:"volume-change"`
}

type soundsSettings struct {
	Enabled bool        `json:"enabled"`
	Volume  int         `json:"volume"`
	Events  soundEvents `json:"events"`
}

func defaultSoundsSettings() soundsSettings {
	on := soundEvent{Enabled: true}
	off := soundEvent{}
	return soundsSettings{
		Enabled: true,
		Volume:  100,
		Events: soundEvents{
			Notification: on, NotificationCritical: on,
			PowerPlug: on, PowerUnplug: on, BatteryLow: on, BatteryFull: on,
			DeviceAdded: off, DeviceRemoved: off,
			Shutter: on, VolumeChange: on,
		},
	}
}

// event returns the setting for a cue name, nil for an unknown name.
func (e *soundEvents) event(name string) *soundEvent {
	switch name {
	case soundNotification:
		return &e.Notification
	case soundNotificationCritical:
		return &e.NotificationCritical
	case soundPowerPlug:
		return &e.PowerPlug
	case soundPowerUnplug:
		return &e.PowerUnplug
	case soundBatteryLow:
		return &e.BatteryLow
	case soundBatteryFull:
		return &e.BatteryFull
	case soundDeviceAdded:
		return &e.DeviceAdded
	case soundDeviceRemoved:
		return &e.DeviceRemoved
	case soundShutter:
		return &e.Shutter
	case soundVolumeChange:
		return &e.VolumeChange
	}
	return nil
}

var soundNames = []string{
	soundNotification, soundNotificationCritical, soundPowerPlug, soundPowerUnplug,
	soundBatteryLow, soundBatteryFull, soundDeviceAdded, soundDeviceRemoved,
	soundShutter, soundVolumeChange,
}

// soundFileExts are the containers pw-play and paplay both decode through
// libsndfile.
var soundFileExts = []string{".oga", ".ogg", ".opus", ".wav", ".flac", ".mp3"}

func (s *soundsSettings) normalize(v *validator) {
	v.rangeI("sounds.volume", &s.Volume, 0, 100)
	for _, name := range soundNames {
		ev := s.Events.event(name)
		path := "sounds.events." + name + ".file"
		ev.File = strings.TrimPrefix(strings.TrimSpace(ev.File), "file://")
		if ev.File == "" || v.err != nil {
			continue
		}
		bad := ""
		if !filepath.IsAbs(ev.File) {
			bad = "must be an absolute path"
		} else if !inSet(soundFileExts, strings.ToLower(filepath.Ext(ev.File))) {
			bad = "must be one of " + strings.Join(soundFileExts, ", ")
		}
		if bad == "" {
			continue
		}
		if v.strict {
			v.err = fmt.Errorf("%s: %s", path, bad)
			return
		}
		ev.File = ""
	}
}

// knownSound gates the `sound <event>` verb so an external caller (ryoshot's
// shutter, the notification server) can only trigger a real cue.
func knownSound(name string) bool {
	var e soundEvents
	return e.event(name) != nil
}

var (
	soundMu    sync.Mutex
	soundReady = map[string]string{} // event -> materialised cache path
	soundLast  = map[string]time.Time{}
)

// soundGap is the least time between two plays of one cue, so a burst of
// notifications or a flapping cable chimes once rather than stacking.
var soundGap = map[string]time.Duration{
	soundNotification:         400 * time.Millisecond,
	soundNotificationCritical: 400 * time.Millisecond,
	soundDeviceAdded:          1 * time.Second,
	soundDeviceRemoved:        1 * time.Second,
}

// soundCacheDir is where embedded clips are written once so a PCM player can
// open them by path. Empty when no home/cache dir is resolvable.
func soundCacheDir() string {
	if d := os.Getenv("XDG_CACHE_HOME"); d != "" {
		return filepath.Join(d, "ryoku", "sounds")
	}
	if h := os.Getenv("HOME"); h != "" {
		return filepath.Join(h, ".cache", "ryoku", "sounds")
	}
	return ""
}

// soundFile materialises an embedded clip to the cache dir once and returns its
// path. Subsequent calls reuse the written file.
func soundFile(name string) (string, bool) {
	soundMu.Lock()
	defer soundMu.Unlock()
	if p, ok := soundReady[name]; ok {
		return p, true
	}
	dir := soundCacheDir()
	if dir == "" {
		return "", false
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", false
	}
	data, err := soundAssets.ReadFile("assets/" + name + ".oga")
	if err != nil {
		return "", false
	}
	dst := filepath.Join(dir, name+".oga")
	// Rewrite a cached clip whose size differs: an update that swaps a built-in
	// sound must not keep playing the old one.
	if st, err := os.Stat(dst); err != nil || st.Size() != int64(len(data)) {
		if err := os.WriteFile(dst, data, 0o644); err != nil {
			return "", false
		}
	}
	soundReady[name] = dst
	return dst, true
}

// soundPlayerArgv picks a PCM player for a clip path at a 0..100 volume. PipeWire's
// pw-play is the session's own player (the same stack wpctl drives); paplay is
// the fallback.
func soundPlayerArgv(file string, volume int) []string {
	if p, err := exec.LookPath("pw-play"); err == nil {
		return []string{p, "--volume=" + strconv.FormatFloat(float64(volume)/100, 'f', 2, 64), file}
	}
	if p, err := exec.LookPath("paplay"); err == nil {
		return []string{p, "--volume=" + strconv.Itoa(volume*65536/100), file}
	}
	return nil
}

// soundPrefs is the live `sounds` setting, or the defaults when no store is
// attached (tests, a daemon that failed to read its file).
func (d *daemon) soundPrefs() soundsSettings {
	if d == nil || d.settings == nil {
		return defaultSoundsSettings()
	}
	d.settings.mu.Lock()
	defer d.settings.mu.Unlock()
	if d.settings.cur == nil {
		return defaultSoundsSettings()
	}
	return d.settings.cur.Sounds
}

// resolveSound picks the file a cue plays: the user's own when it still exists,
// else the built-in clip.
func resolveSound(name, custom string) (string, bool) {
	if custom != "" {
		if st, err := os.Stat(custom); err == nil && st.Mode().IsRegular() {
			return custom, true
		}
	}
	return soundFile(name)
}

// playSound fires an event cue without blocking the caller, honouring the
// master switch, the cue's own switch, its custom file and the volume.
func (d *daemon) playSound(name string) {
	prefs := d.soundPrefs()
	ev := prefs.Events.event(name)
	if ev == nil || !prefs.Enabled || !ev.Enabled || prefs.Volume == 0 {
		return
	}
	if gap := soundGap[name]; gap > 0 {
		soundMu.Lock()
		now := time.Now()
		if now.Sub(soundLast[name]) < gap {
			soundMu.Unlock()
			return
		}
		soundLast[name] = now
		soundMu.Unlock()
	}
	playSoundFile(name, ev.File, prefs.Volume)
}

// playSoundFile plays one cue's resolved file in the background. The
// volume-change cue waits 50 ms first so the sink level has settled before it
// plays.
func playSoundFile(name, custom string, volume int) {
	go func() {
		if name == soundVolumeChange {
			time.Sleep(50 * time.Millisecond)
		}
		file, ok := resolveSound(name, custom)
		if !ok {
			return
		}
		argv := soundPlayerArgv(file, volume)
		if argv == nil {
			return
		}
		_ = exec.Command(argv[0], argv[1:]...).Run()
	}()
}

// registerSoundCalls adds `sounds.preview`: play a cue now so the Hub can
// audition it, regardless of its switch. An explicit file previews a pick
// before it is saved.
func (d *daemon) registerSoundCalls() {
	d.registerCall("sounds.preview", func(raw json.RawMessage) (any, error) {
		var p struct {
			Event string `json:"event"`
			File  string `json:"file"`
		}
		if len(raw) > 0 {
			if err := json.Unmarshal(raw, &p); err != nil {
				return nil, err
			}
		}
		prefs := d.soundPrefs()
		ev := prefs.Events.event(p.Event)
		if ev == nil {
			return nil, fmt.Errorf("unknown sound %q", p.Event)
		}
		file := strings.TrimPrefix(p.File, "file://")
		if file == "" {
			file = ev.File
		}
		playSoundFile(p.Event, file, prefs.Volume)
		return nil, nil
	})
}

// readTrim reads a sysfs attribute and trims it, returning "" on any error.
func readTrim(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}
