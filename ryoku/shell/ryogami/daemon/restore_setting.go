package main

func (d *daemon) restoreOnStartup() bool {
	return d.settingBool("restoreOnStartup")
}
