package main

import (
	"encoding/json"
	"net/http"
	"strings"
)

// handleFix is POST /api/fix: the dashboard's Fix with AI buttons. It resolves
// the problem against the live scans and opens the user's agent harness in a
// terminal. It starts an agent that can change the machine, so a page on
// another site must not reach it: the Origin must be this dashboard, and the
// JSON content type forces a CORS preflight the daemon never grants.
func handleFix(w http.ResponseWriter, r *http.Request) {
	if !loopbackOrigin(r) || !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	var req fixRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	req.Kind = strings.TrimSpace(req.Kind)
	fail := func(code int, err error) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(code)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
	}
	display, brief, err := buildFix(req)
	if err != nil {
		fail(http.StatusUnprocessableEntity, err)
		return
	}
	launch, err := planFix(display, brief)
	if err == nil {
		err = openFixTerminal(launch)
	}
	if err != nil {
		fail(http.StatusServiceUnavailable, err)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "display": display, "harness": launch.Harness})
}
