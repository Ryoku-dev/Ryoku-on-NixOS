package main

func init() {
	watchSetting("paths.", func(d *daemon, key string, _ interface{}) {
		switch key {
		case "paths.wallpaper", "paths.videoWallpaper":
			d.reloadConfig()
			libraryWatch.signalRewatch()
			go d.rescan(true)
		}
	})
}
