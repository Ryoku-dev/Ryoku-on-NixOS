package main

// Re-lays the current clip so a new decode cap applies now, not at the next apply.
func init() {
	watchSetting("resource_tier", func(d *daemon, _ string, _ interface{}) {
		tier := d.settingString("resource_tier")
		if tier != "low" && tier != "medium" && tier != "high" {
			return
		}
		d.cfgMu.Lock()
		d.cfg.ResourceTier = tier
		d.cfgMu.Unlock()
		if d.video.Playing() {
			go d.restoreOutputs()
		}
	})
}
