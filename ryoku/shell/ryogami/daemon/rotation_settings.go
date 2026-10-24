package main

// Rotation follows the settings rather than an explicit start/stop RPC.

func init() {
	onStart(func(d *daemon) { d.syncRandomRotation() })
	watchSetting("general.random", func(d *daemon, _ string, _ interface{}) { d.syncRandomRotation() })
}

// Shared with the schedule's random target so both draw from the pool the user configured.
func (d *daemon) randomPoolConfig() (types []string, favOnly bool) {
	if d.settingBool("general.randomIncludeStatic") {
		types = append(types, "static")
	}
	if d.settingBool("general.randomIncludeVideo") {
		types = append(types, "video")
	}
	if d.settingBool("general.randomIncludeWE") {
		types = append(types, "we")
	}
	favOnly = d.settingBool("general.randomIncludeFavourites")
	return types, favOnly
}

func (d *daemon) syncRandomRotation() {
	if !d.settingBool("general.randomRotate") {
		d.random.stop()
		return
	}
	types, favOnly := d.randomPoolConfig()
	if len(types) == 0 {
		d.random.stop()
		return
	}
	interval := int64(d.settingNumber("general.randomInterval"))
	if interval < 10 {
		interval = 10
	}
	d.random.start(interval, types, favOnly, func() { d.randomPick(types, favOnly) })
}
