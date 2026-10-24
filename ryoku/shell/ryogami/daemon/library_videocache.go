package main

import "time"

func init() {
	onStart(func(d *daemon) { go d.videoCacheRetentionLoop() })
	registerAction("ClearVideoCache", actionClearVideoCache)
}

func (d *daemon) videoCacheRetentionLoop() {
	for {
		if d.settingBool("performance.autoCleanVideoCache") {
			pruneLivewallCache(int(d.settingNumber("performance.videoCacheDays")))
		}
		time.Sleep(24 * time.Hour)
	}
}

// A playing clip reads its transcode from this cache, so it stops and restores around the wipe.
func actionClearVideoCache(d *daemon, args map[string]interface{}) (interface{}, error) {
	days := 0
	if v, ok := args["days"].(float64); ok {
		days = int(v)
	}
	playing := d.video.Playing()
	if playing {
		d.video.Stop()
	}
	removed, freed := pruneLivewallCache(days)
	if playing {
		d.restoreOutputs()
	}
	return map[string]interface{}{"removed": removed, "freed": freed}, nil
}
