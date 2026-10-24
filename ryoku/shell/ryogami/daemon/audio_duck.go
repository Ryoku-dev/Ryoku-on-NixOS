package main

import (
	"bufio"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Ducking mutes the wallpaper's own streams: the daemon does not own the mixer.

var wallpaperAudioBins = []string{
	"ryogami-live", "skwd-paper-v2", "skwd-wall-vk", "paper-vk",
}

var duckState struct {
	mu     sync.Mutex
	ducked bool
}

func pactlBin() string {
	p, err := exec.LookPath("pactl")
	if err != nil {
		return ""
	}
	return p
}

func parseOtherAudio(out string, wallpaperBins []string) bool {
	inSet := func(bin string) bool {
		for _, w := range wallpaperBins {
			if bin == w {
				return true
			}
		}
		return false
	}
	var corked, wallpaper bool
	fresh := true
	other := false
	flush := func() {
		if fresh {
			return
		}
		if !wallpaper && !corked {
			other = true
		}
	}
	for _, line := range strings.Split(out, "\n") {
		t := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(t, "Sink Input #"):
			flush()
			corked, wallpaper, fresh = false, false, false
		case strings.HasPrefix(t, "Corked:"):
			corked = strings.EqualFold(strings.TrimSpace(t[len("Corked:"):]), "yes")
		case strings.Contains(t, "application.process.binary"):
			if inSet(unquoteProp(t)) {
				wallpaper = true
			}
		case strings.Contains(t, "media.role"):
			if strings.EqualFold(unquoteProp(t), "wallpaper") {
				wallpaper = true
			}
		case strings.Contains(t, "application.name"):
			if v := strings.ToLower(unquoteProp(t)); strings.Contains(v, "ryogami") || strings.Contains(v, "wallpaper") {
				wallpaper = true
			}
		}
	}
	flush()
	return other
}

func unquoteProp(line string) string {
	i := strings.Index(line, "=")
	if i < 0 {
		return ""
	}
	return strings.Trim(strings.TrimSpace(line[i+1:]), "\"")
}

func otherAudioPlaying() bool {
	bin := pactlBin()
	if bin == "" {
		return false
	}
	out, err := exec.Command(bin, "list", "sink-inputs").Output()
	if err != nil {
		return false
	}
	return parseOtherAudio(string(out), wallpaperAudioBins)
}

func (d *daemon) evaluateDuck() {
	duckState.mu.Lock()
	defer duckState.mu.Unlock()
	want := d.settingBool("playback.muteOnOtherAudio") && otherAudioPlaying()
	if want == duckState.ducked {
		return
	}
	duckState.ducked = want
	if want {
		m := true
		d.surface.setAudio(&m, nil, nil)
		if d.paper != nil {
			_ = d.paper.setAudio(&m, nil, nil)
		}
		return
	}
	d.restoreDuckedAudio()
}

func (d *daemon) restoreDuckedAudio() {
	state := map[string]map[string]interface{}{}
	loadJSON(filepath.Join(d.config().cacheDir(), "outputs.json"), &state)
	def := wallAudioDefaults()
	if len(state) == 0 {
		m, vol := def.mute, def.volume
		d.surface.setAudio(&m, &vol, nil)
		return
	}
	for out, e := range state {
		m, vol := entryAudio(e, def)
		var outs []string
		if out != "*" {
			outs = []string{out}
		}
		d.surface.setAudio(&m, &vol, outs)
		if d.paper != nil {
			_ = d.paper.setAudio(&m, &vol, outs)
		}
	}
}

func (d *daemon) watchOtherAudio() {
	if pactlBin() == "" {
		return
	}
	d.evaluateDuck()
	for {
		cmd := exec.Command(pactlBin(), "subscribe")
		// The unit stops only the daemon, so the watcher must end with it rather than outlive it.
		cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM}
		stdout, err := cmd.StdoutPipe()
		if err != nil || cmd.Start() != nil {
			time.Sleep(2 * time.Second)
			continue
		}
		sc := bufio.NewScanner(stdout)
		pending := make(chan struct{}, 1)
		go func() {
			for range pending {
				time.Sleep(150 * time.Millisecond)
				select {
				case <-pending:
				default:
				}
				d.evaluateDuck()
			}
		}()
		for sc.Scan() {
			if !strings.Contains(sc.Text(), "sink-input") {
				continue
			}
			select {
			case pending <- struct{}{}:
			default:
			}
		}
		close(pending)
		_ = cmd.Wait()
		time.Sleep(time.Second)
	}
}

func init() {
	onStart(func(d *daemon) { go d.watchOtherAudio() })
	watchSetting("playback.muteOnOtherAudio", func(d *daemon, _ string, _ interface{}) {
		d.evaluateDuck()
	})
}
