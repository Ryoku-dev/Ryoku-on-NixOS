package main

func (d *daemon) dispatchWorkshop(req *request, p map[string]interface{}) (response, bool) {
	switch req.Method {
	case "workshop.list":
		return d.workshopList(req), true
	case "workshop.search":
		return d.workshopSearch(req, p), true
	case "workshop.download":
		return d.workshopDownload(req, p), true
	case "workshop.properties":
		return d.workshopProperties(req, p), true
	case "workshop.setProperty":
		return d.workshopSetProperty(req, p), true
	}
	return response{}, false
}

func (d *daemon) workshopList(req *request) response {
	rows := []Entry{}
	if d.featureSteam() {
		for _, e := range d.store.list(false) {
			if e.Type == "we" {
				rows = append(rows, e)
			}
		}
	}
	return ok(req.ID, map[string]interface{}{"count": len(rows), "items": rows})
}

func (d *daemon) workshopSearch(req *request, p map[string]interface{}) response {
	if !d.featureSteam() {
		return errResp(req.ID, 5, "Wallpaper Engine support is disabled")
	}
	params := steamSearchParams{
		query:        strParam(p, "query", ""),
		queryType:    normalizeQueryType(int(intParam(p, "queryType", 3))),
		days:         int(intParam(p, "trendDays", 7)),
		tags:         strsParam(p, "requiredTags"),
		excludedTags: strsParam(p, "excludedTags"),
		page:         int(intParam(p, "page", 1)),
		numPerPage:   int(intParam(p, "numPerPage", 30)),
		allowNsfw:    boolParam(p, "allowNsfw", false),
	}
	generation := intParam(p, "generation", 0)
	ctx, finish, stale := d.sources.beginSearch(req.ConnectionID, "workshop:steam", generation, searchFetchTimeout)
	if stale {
		return errResp(req.ID, 4, "search superseded")
	}
	defer finish()
	page, err := d.workshop.search(ctx, params)
	if ctxErr := ctx.Err(); ctxErr != nil {
		err = ctxErr
	}
	if err != nil {
		return errResp(req.ID, 4, searchError(err))
	}
	d.queueRemoteThumbs(req.ConnectionID, "workshop:steam", "steam", generation, thumbJobs(page))
	return ok(req.ID, map[string]interface{}{
		"results":     d.workshop.items(page),
		"currentPage": page.currentPage,
		"lastPage":    page.lastPage,
		"generation":  p["generation"],
	})
}

func (d *daemon) workshopDownload(req *request, p map[string]interface{}) response {
	if !d.featureSteam() {
		return errResp(req.ID, 5, "Wallpaper Engine support is disabled")
	}
	id := strParam(p, "id", "")
	if !allDigits(id) {
		return errResp(req.ID, 1, "missing/invalid workshop id")
	}
	status, openURL := d.workshop.download(id)
	res := map[string]interface{}{"id": id, "status": status}
	if openURL != "" {
		res["url"] = openURL
	}
	return ok(req.ID, res)
}

func (d *daemon) workshopProperties(req *request, p map[string]interface{}) response {
	weID := weIDParam(p)
	props, fps, globalFps := d.workshop.properties(weID)
	if props == nil {
		props = []weProperty{}
	}
	return ok(req.ID, map[string]interface{}{
		"weId": weID, "properties": props, "fps": fps, "globalFps": globalFps,
	})
}

func (d *daemon) workshopSetProperty(req *request, p map[string]interface{}) response {
	weID := weIDParam(p)
	if !validWeID(weID) {
		return errResp(req.ID, 1, "invalid workshop id")
	}
	w := d.workshop
	name := strParam(p, "name", "")
	switch v, hasFps := p["fps"]; {
	case hasFps:
		// A number pins this scene's rate; null returns it to the global rate.
		if f, ok := v.(float64); ok {
			w.props.setFps(weID, clampFps(int(f)))
		} else {
			w.props.setFps(weID, 0)
		}
	case boolParam(p, "reset", false) && name == "":
		w.props.resetAll(weID)
	case name == "":
		return errResp(req.ID, 1, "missing 'name' parameter")
	case boolParam(p, "reset", false):
		w.props.resetValue(weID, name)
	default:
		w.props.setValue(weID, name, p["value"])
	}
	reapplied := w.reapplyIfCurrent(weID)
	props, fps, globalFps := w.properties(weID)
	if props == nil {
		props = []weProperty{}
	}
	return ok(req.ID, map[string]interface{}{
		"weId": weID, "properties": props, "reapplied": reapplied, "fps": fps, "globalFps": globalFps,
	})
}

func weIDParam(p map[string]interface{}) string {
	if id := strParam(p, "weId", ""); id != "" {
		return id
	}
	return strParam(p, "we_id", "")
}

func normalizeQueryType(qt int) int {
	switch qt {
	case 0, 1, 3, 9, 21:
		return qt
	default:
		return 3
	}
}
