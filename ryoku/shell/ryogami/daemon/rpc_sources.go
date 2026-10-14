package main

func (d *daemon) dispatchSources(req *request, p map[string]interface{}) (response, bool) {
	s := d.sources
	switch req.Method {
	case "source.providers":
		return s.providers(req.ID), true
	case "source.search":
		return s.search(req.ID, req.ConnectionID, p), true
	case "source.preview":
		return s.preview(req.ID, p), true
	case "source.download":
		return s.download(req.ID, p), true
	case "source.cancel":
		return s.cancel(req.ID, p), true
	case "wallhaven.collections":
		return s.wallhavenCollections(req.ID, p), true
	}
	return errResp(req.ID, -32601, "unknown method: "+req.Method), true
}
