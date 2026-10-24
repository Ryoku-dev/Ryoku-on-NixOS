package main

func init() {
	watchSetting("matugen.videoFrame", func(d *daemon, _ string, _ interface{}) {
		d.reloadConfig()
		// Republishing re-extracts the still at the new second, so the palette follows it.
		d.restoreOutputs()
	})
}
