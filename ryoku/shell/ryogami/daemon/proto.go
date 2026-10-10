package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// The wire mirrors the Rust daemon this Go port replaces, which itself mirrored
// ryoku-shell's line pub/sub: one unix socket serves plain verb lines, JSON-RPC
// request lines, `subscribe <topic>` streams, and pushed events after a JSON
// `subscribe` request.

type request struct {
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
	ID     int64           `json:"id"`
}

type response struct {
	ID     int64       `json:"id"`
	Result interface{} `json:"result,omitempty"`
	Error  *rpcError   `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type event struct {
	Event string      `json:"event"`
	Data  interface{} `json:"data"`
}

func ok(id int64, result interface{}) response {
	return response{ID: id, Result: result}
}

func errResp(id int64, code int, msg string) response {
	return response{ID: id, Error: &rpcError{Code: code, Message: msg}}
}

// params unmarshals the request params into a map; a null/absent params is an
// empty map so lookups stay uniform.
func (r *request) params() map[string]interface{} {
	m := map[string]interface{}{}
	if len(r.Params) > 0 {
		_ = json.Unmarshal(r.Params, &m)
	}
	return m
}

func strParam(p map[string]interface{}, key, def string) string {
	if v, ok := p[key].(string); ok {
		return v
	}
	return def
}

func boolParam(p map[string]interface{}, key string, def bool) bool {
	if v, ok := p[key].(bool); ok {
		return v
	}
	return def
}

func intParam(p map[string]interface{}, key string, def int64) int64 {
	if v, ok := p[key].(float64); ok {
		return int64(v)
	}
	return def
}

func strsParam(p map[string]interface{}, key string) []string {
	out := []string{}
	if a, ok := p[key].([]interface{}); ok {
		for _, v := range a {
			if s, ok := v.(string); ok {
				out = append(out, s)
			}
		}
	}
	return out
}

func socketPath() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		// A manual/non-systemd launch still needs a common client/daemon path,
		// but never place the socket directly in the shared /tmp namespace.
		// Prefer the user's cache tree; only fall back to a UID-specific temp
		// directory if the platform cannot resolve a user cache directory.
		if cache, err := os.UserCacheDir(); err == nil && cache != "" {
			dir = filepath.Join(cache, "ryogami", "runtime")
		} else {
			dir = filepath.Join(os.TempDir(), fmt.Sprintf("ryogami-%d", os.Geteuid()))
		}
	}
	return filepath.Join(dir, "ryogami.sock")
}
