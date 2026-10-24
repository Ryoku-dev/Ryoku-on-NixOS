package main

func (d *daemon) dispatchSchedule(req *request, p map[string]interface{}) (response, bool) {
	switch req.Method {
	case "schedule.get":
		return ok(req.ID, d.scheduleSnapshot()), true
	case "schedule.set":
		if v, has := p["enabled"]; has {
			if b, isBool := v.(bool); isBool {
				_ = d.setSetting("schedule.enabled", b)
			}
		}
		if v, has := p["applyOnStart"]; has {
			if b, isBool := v.(bool); isBool {
				_ = d.setSetting("schedule.applyOnStart", b)
			}
		}
		if v, has := p["latitude"]; has {
			if s, isStr := v.(string); isStr {
				_ = d.setSetting("schedule.latitude", s)
			}
		}
		if v, has := p["longitude"]; has {
			if s, isStr := v.(string); isStr {
				_ = d.setSetting("schedule.longitude", s)
			}
		}
		if v, has := p["rules"]; has {
			if arr, isArr := v.([]interface{}); isArr {
				_ = d.setSetting("schedule.rules", arr)
			}
		}
		scheduleReload()
		return ok(req.ID, d.scheduleSnapshot()), true
	}
	return errResp(req.ID, -32601, "unknown method: "+req.Method), true
}
