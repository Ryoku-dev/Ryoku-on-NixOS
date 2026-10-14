package main

import "strings"

func (d *daemon) dispatchExtended(req *request, p map[string]interface{}) (response, bool) {
	switch {
	case strings.HasPrefix(req.Method, "lighting."):
		return d.dispatchLighting(req, p)
	case strings.HasPrefix(req.Method, "settings."):
		return d.dispatchSettings(req, p)
	case strings.HasPrefix(req.Method, "source."), strings.HasPrefix(req.Method, "wallhaven."):
		return d.dispatchSources(req, p)
	case strings.HasPrefix(req.Method, "workshop."):
		return d.dispatchWorkshop(req, p)
	case strings.HasPrefix(req.Method, "theme."):
		return d.dispatchTheme(req, p)
	case strings.HasPrefix(req.Method, "palette."):
		return d.dispatchPalette(req, p)
	case strings.HasPrefix(req.Method, "schedule."):
		return d.dispatchSchedule(req, p)
	case strings.HasPrefix(req.Method, "semantic."):
		return d.dispatchSemantic(req, p)
	case req.Method == "library.status":
		return d.dispatchLibrary(req, p)
	case strings.HasPrefix(req.Method, "task."):
		return d.dispatchTasks(req, p)
	case req.Method == "power.status":
		return ok(req.ID, d.powerStatus(powerOnBattery())), true
	}
	return response{}, false
}
