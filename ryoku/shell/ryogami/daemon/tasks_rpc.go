package main

func (d *daemon) dispatchTasks(req *request, p map[string]interface{}) (response, bool) {
	switch req.Method {
	case "task.list":
		return ok(req.ID, map[string]interface{}{"tasks": d.tasks.list()}), true
	case "task.control":
		if err := d.tasks.control(strParam(p, "id", ""), strParam(p, "action", "")); err != nil {
			return errResp(req.ID, 2, err.Error()), true
		}
		return ok(req.ID, map[string]interface{}{"ok": true}), true
	}
	return response{}, false
}
