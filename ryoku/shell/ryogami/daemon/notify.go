package main

import (
	"os/exec"
	"path/filepath"
	"strings"
)

// Only user-visible applies notify; a restore or live reload repaints the same wallpaper.

func init() {
	afterApply(func(d *daemon, ev applyEvent) {
		if restoreLikeApply(ev.Reason) {
			return
		}
		if !d.settingBool("general.notifyOnWallpaperChange") {
			return
		}
		d.notifyWallpaperChange(ev)
	})
}

func (d *daemon) notifyWallpaperChange(ev applyEvent) {
	bin, err := exec.LookPath("notify-send")
	if err != nil {
		return
	}
	body := strings.TrimSuffix(ev.Name, filepath.Ext(ev.Name))
	if body == "" {
		body = ev.Name
	}
	args := []string{"-a", "Ryogami"}
	if icon := d.notifyIcon(ev); icon != "" {
		args = append(args, "-i", icon)
	}
	args = append(args, "Wallpaper changed", body)
	cmd := exec.Command(bin, args...)
	if err := cmd.Start(); err != nil {
		return
	}
	go func() { _ = cmd.Wait() }()
}

func (d *daemon) notifyIcon(ev applyEvent) string {
	if e, ok := d.store.get(ev.Key); ok && e.Thumb != "" && fileExists(e.Thumb) {
		return e.Thumb
	}
	if ev.Type == "static" && fileExists(ev.Path) {
		return ev.Path
	}
	return ""
}
