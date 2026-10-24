package main

func (d *daemon) dispatchLibrary(req *request, p map[string]interface{}) (response, bool) {
	if req.Method == "library.status" {
		return ok(req.ID, d.libraryStatus()), true
	}
	return response{}, false
}
