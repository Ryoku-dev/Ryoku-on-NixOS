package main

import (
	"hash/fnv"
	"io/fs"
	"path/filepath"
	"strconv"
	"strings"
)

// librarySignature is an order-stable fingerprint of every media file under the
// wallpaper and video dirs (path, mtime, size). Any add, remove, or in-place
// replace changes it. It mirrors collectMedia's walk filters (skip dotdirs and
// the cache subtree, keep only catalogued extensions) so it tracks exactly the
// files a rescan would, and never trips on thumbnails the daemon writes.
func (d *daemon) librarySignature() uint64 {
	cfg := d.config()
	absCache, _ := filepath.Abs(cfg.cacheDir())
	h := fnv.New64a()
	seen := map[string]bool{}
	for _, root := range []string{cfg.wallpaperDir(), cfg.videoDir()} {
		if root == "" || seen[root] {
			continue
		}
		seen[root] = true
		_ = filepath.WalkDir(root, func(path string, e fs.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if e.IsDir() {
				if abs, _ := filepath.Abs(path); abs == absCache {
					return filepath.SkipDir
				}
				if path != root && strings.HasPrefix(e.Name(), ".") {
					return filepath.SkipDir
				}
				return nil
			}
			ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(e.Name()), "."))
			if !imageExts[ext] && !videoExts[ext] {
				return nil
			}
			info, ierr := e.Info()
			if ierr != nil {
				return nil
			}
			h.Write([]byte(path))
			h.Write([]byte{0})
			h.Write([]byte(strconv.FormatInt(info.ModTime().UnixNano(), 10)))
			h.Write([]byte{0})
			h.Write([]byte(strconv.FormatInt(info.Size(), 10)))
			h.Write([]byte{0})
			return nil
		})
	}
	return h.Sum64()
}
