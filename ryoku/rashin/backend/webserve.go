package main

import (
	"io/fs"
	"net/http"
	"strings"
)

// webHandler serves the built console. Vite names every bundle by content
// hash under assets/, so those are immutable for a year; index.html and the
// fonts are not hashed and must never be pinned, or a console left open
// across an update keeps the old shell.
func webHandler(root fs.FS) http.Handler {
	files := http.FileServerFS(root)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/assets/") {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		} else {
			w.Header().Set("Cache-Control", "no-cache")
		}
		files.ServeHTTP(w, r)
	})
}
