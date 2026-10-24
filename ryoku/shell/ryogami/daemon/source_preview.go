package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
)

// Wallhaven previews cache as wallhaven-full so a later download imports them without refetching.
func (s *sources) remotePreviewPath(source, id, ext string) string {
	return filepath.Join(s.d.config().cacheDir(), "remote-preview", safeSeg(source), safeSeg(id)+"."+safeSeg(ext))
}

func (s *sources) fetchImage(ctx context.Context, rawURL, dest string, policy func(string) error) error {
	return s.fetchToFile(ctx, rawURL, dest, sniffImage, previewMaxEncoded, policy, nil)
}

func (s *sources) preview(reqID int64, p map[string]interface{}) response {
	source := strParam(p, "source", "")
	if providerSpec(source) == nil {
		return errResp(reqID, -32602, "unknown source '"+source+"'")
	}
	id := strParam(p, "id", "")
	fullURL := strParam(p, "fullUrl", "")
	previewSource := source
	switch source {
	case "youtube":
		if !youtubeSafeID(id) {
			return errResp(reqID, -32602, "invalid youtube id")
		}
		fullURL = youtubePreviewURL(id)
	case "wallhaven":
		previewSource = "wallhaven-full"
	}
	if id == "" || fullURL == "" {
		return errResp(reqID, -32602, "missing id/fullUrl")
	}
	if err := requireSource(source, fullURL); err != nil {
		return errResp(reqID, -1, "blocked preview url")
	}
	dest := s.remotePreviewPath(previewSource, id, extFromURL(fullURL))
	key := "preview:" + dest
	if !s.beginInflight(key) {
		return ok(reqID, map[string]interface{}{"id": id, "status": "fetching"})
	}
	res, okReserve := s.previews.tryReserve()
	if !okReserve {
		s.endInflight(key)
		return errResp(reqID, -32000, "preview queue is full; retry shortly")
	}
	go func() {
		defer s.endInflight(key)
		slot := res.acquire(nil)
		defer slot.release()
		if fi, err := os.Stat(dest); err == nil && fi.Size() > 0 {
			if checkFile(dest, sniffImage) == nil {
				s.d.broadcast(evPreviewReady, map[string]interface{}{"id": id, "path": dest})
				return
			}
			os.Remove(dest)
		}
		ctx, cancel := context.WithTimeout(context.Background(), previewFetchTimeout)
		defer cancel()
		policy := func(u string) error { return requireSource(source, u) }
		if err := s.fetchImage(ctx, fullURL, dest, policy); err != nil {
			fmt.Fprintf(os.Stderr, "ryogami: preview %s failed: %v\n", id, err)
			return
		}
		s.d.broadcast(evPreviewReady, map[string]interface{}{"id": id, "path": dest})
	}()
	return ok(reqID, map[string]interface{}{"id": id, "status": "fetching"})
}
